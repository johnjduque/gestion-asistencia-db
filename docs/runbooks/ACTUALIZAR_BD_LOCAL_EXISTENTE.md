---
status: active
type: runbook
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# Actualizar una base local existente hasta develop (sin perder datos)

Para quien tiene su propia `gestionasistenciadb` local con datos de prueba y la base se quedó atrás: le faltan objetos de las
migraciones nuevas (por ejemplo la 33 de HU018/HU019 o la 37 y 38 de tomas por puntos de control) y no tiene la tabla
`dbo.MigracionAplicada`, así que `scripts/migrar.ps1 -Modo Estado` muestra todas las migraciones como pendientes.

En ese caso **no** sirve ninguna de estas dos salidas:

- `migrar.ps1 -Modo Baseline` sin más: registraría todas las migraciones como aplicadas y nunca se ejecutarían las que faltan.
- `migrar.ps1 -Modo Aplicar` directo: intentaría ejecutar otra vez las migraciones viejas (05 a 16), y varias se detienen con
  `THROW` porque sus precondiciones ya no se cumplen.

El procedimiento usa `-Modo Detectar`, que mira en la base el efecto real de cada migración (tablas, columnas, índices,
restricciones, procedimientos y filas de catálogo, según `scripts/migrar-marcadores.json`), y `-Modo Baseline -SoloDetectadas`,
que registra solo las que ya están. Después `-Modo Aplicar` ejecuta, en orden, las que faltan.

Se ensayó completo (2026-11-13) sobre una copia del esquema de develop del 2026-11-09 (commit `8f18b76`, antes de la migración 17)
en un contenedor desechable: terminó con `pendientes=0 deriva=0`, las 42 migraciones detectadas y el mismo esquema que un
despliegue limpio. Detalle en `docs/work-items/VAL-migrar-detectar/VALIDATION.md`.

Todos los comandos se ejecutan en PowerShell desde la raíz del repositorio de BD. Los scripts leen la clave de SQL Server de
`.env` (`SQL_CONTAINER_PASSWORD`); no la escriba en la consola ni la comparta. El contenedor por defecto es
`sql_server_asistencias` y la base `gestionasistenciadb`.

## 1. Detener el backend

Detenga el backend (la aplicación Spring en el puerto 8080). Sus conexiones y trabajos programados usan la base. Compruebe:

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue   # no debe devolver nada
```

## 2. Respaldo (obligatorio)

Opción A: respaldo `COPY_ONLY` con verificación, dentro del contenedor:

```powershell
$pw = ((Get-Content .env | Where-Object { $_ -match '^\s*SQL_CONTAINER_PASSWORD=' }) -split '=', 2)[1].Trim()
$bak = "/var/opt/mssql/backup/gestionasistenciadb_antes_migrar_$(Get-Date -Format 'yyyyMMdd-HHmm').bak"
docker exec -u 0 sql_server_asistencias bash -c "mkdir -p /var/opt/mssql/backup && chown mssql /var/opt/mssql/backup"
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -b `
  -Q "BACKUP DATABASE [gestionasistenciadb] TO DISK = N'$bak' WITH COPY_ONLY, CHECKSUM, INIT, STATS = 25;"
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -b `
  -Q "RESTORE VERIFYONLY FROM DISK = N'$bak' WITH CHECKSUM;"
# Copia fuera del contenedor (por si el contenedor se pierde):
docker cp "sql_server_asistencias:$bak" .\respaldo_antes_migrar.bak
$bak   # anote la ruta: la necesita para volver atrás
```

`RESTORE VERIFYONLY` debe terminar con `The backup set on file 1 is valid.` Si falla, no siga.

Opción B: con el script de Infra (respaldo con `CHECKSUM` en `/var/opt/mssql/backup/gestionasistenciadb_QA_<fecha>.bak`):

```powershell
..\Repositorio_GestionAsistenciaInfra\infra.ps1 db-reset-qa -Mode Snapshot
```

Anote el nombre del archivo que imprime. Verifíquelo igual con `RESTORE VERIFYONLY` (comando de la opción A).

## 3. Traer develop

```powershell
git switch develop
git pull
```

## 4. Detectar qué tiene la base (solo lectura)

```powershell
.\scripts\migrar.ps1 -Modo Detectar
```

No escribe nada: ni ejecuta migraciones ni crea `dbo.MigracionAplicada`. Imprime una línea por migración y un resumen:

- `MIGRAR_DETECTAR_APLICADA_DETECTADA`: todos sus marcadores están en la base.
- `MIGRAR_DETECTAR_AUSENTE`: ninguno está.
- `MIGRAR_DETECTAR_PARCIAL`: algunos sí y otros no; debajo salen las líneas `falta: ...`.
- `fuera_de_orden=1`: detectada después de una ausente. No se registra; `Aplicar` la vuelve a ejecutar en su orden (son
  idempotentes). Es normal en la 20 (entró a develop antes que la 17) y en la 36 (solo retira objetos que nunca existieron).
- `solo_retiro=1`: la migración solo borra cosas.
- Resumen: `MIGRAR_DETECTAR_RESUMEN total=42 detectadas=.. ausentes=.. parciales=.. sin_marcadores=0 contigua_hasta=NN (...)`.
  `contigua_hasta` es la última migración del tramo continuo que ya está completo.

Para una base del 9 de noviembre lo esperado es `contigua_hasta=16`, la 20 y la 36 detectadas fuera de orden, el resto
`AUSENTE` y `parciales=0`.

**Si aparece alguna `PARCIAL`, deténgase** y envíe la salida completa de este paso: hay que decidir a mano (una migración
interrumpida o un objeto creado a mano). No siga con los pasos 5 y 6.

Para quien revisa: el caso más común es una base mantenida solo con `deploy_schema.ps1`, que crea las tablas nuevas pero no borra
lo que una migración retira (por ejemplo, sale `PARCIAL` la 05 porque sigue existiendo `usp_registrar_docente_en_grupo_autonomo`).
Si las líneas `falta:` son de ese tipo, la decisión suele ser re-ejecutar esas migraciones: en el paso 5 se usa
`.\scripts\migrar.ps1 -Modo Baseline -SoloDetectadas -ReaplicarParciales`, que no registra la `PARCIAL` ni nada de lo que va
después de ella, y el paso 6 las ejecuta en orden. Se probó con un respaldo real de desarrollo del 2026-11-09 (tres `PARCIAL`:
05, 13 y 14): `Aplicar` ejecutó las 42 sin errores y quedaron todas detectadas.

## 5. Registrar lo que ya está

```powershell
.\scripts\migrar.ps1 -Modo Baseline -SoloDetectadas
```

Repite la detección; si hay alguna `PARCIAL` no registra nada y termina con código 1. Si no, crea `dbo.MigracionAplicada` (si falta)
y registra como `BASELINE` solo el tramo continuo detectado (en el caso típico, las 17 migraciones de la 05 a la 16). Las detectadas
fuera de orden quedan `PENDIENTE` (línea `MIGRAR_DETECTADA_FUERA_DE_ORDEN`).

## 6. Aplicar las que faltan

```powershell
.\scripts\migrar.ps1 -Modo Aplicar
```

Ejecuta en orden de versión todas las pendientes (17, 18, 19, 20, 21, ... 42) y registra cada una como `APLICADA`. En el ensayo
tardó unos 2 minutos. Debe terminar con `MIGRAR_RESUMEN modo=Aplicar ... pendientes=0 deriva=0`.

Si sale `MIGRAR_FALLO <migración>`: deténgase y envíe la salida. Las migraciones anteriores a la que falló quedan aplicadas y
registradas; la que falló no queda registrada. Para volver al estado inicial use el paso 10.

## 7. Desplegar procedimientos, vistas, permisos y catálogos (necesario)

Las migraciones cambian estructura y catálogos, pero varias dejan a `deploy_schema.ps1` el despliegue de procedimientos, mensajes,
parámetros, plantillas y permisos (lo dicen en su encabezado; por ejemplo la 19). En el ensayo, después del paso 6 faltaban 6
procedimientos (`usp_evaluar_alertas_inasistencia_grupo`, `usp_consultar_alertas_estudiante`, ...), los mensajes `ALR_*` y `RCN_*`,
parámetros de `ALERTA_INASISTENCIA`, cuatro plantillas de cancelación y los permisos, y dos procedimientos
(`usp_ejecutar_cierre_masivo_periodo` y `usp_consultar_resumen_asistencia_grupo_docente_paginado`) tenían una versión anterior. Después de `deploy_schema.ps1` la base quedó igual a un despliegue limpio. Por eso este paso no es opcional.

Qué hace `deploy_schema.ps1` sobre una base con datos:

- Tablas: solo crea las que faltan (`IF OBJECT_ID ... IS NULL`); no cambia columnas ni borra datos.
- Funciones, vistas y procedimientos: `CREATE OR ALTER` (quedan con el texto de develop).
- Seguridad: roles y permisos (idempotente).
- Semillas: `MERGE` por clave. **Ojo**: `schema/seed/03_parametro.sql` vuelve a poner el valor de fábrica en los parámetros base
  (por ejemplo `ASISTENCIA/UMBRAL_ALERTA_PERDIDA`), y las semillas de datos de demostración (`11` a `14`) devuelven a su valor
  original las filas de demostración con id fijo (usuarios, programas y grupos de ejemplo). Los datos que usted creó con otros id
  no se tocan.

Antes del despliegue, guarde los parámetros que cambió para reponerlos después:

```powershell
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -b -h -1 -W -d gestionasistenciadb `
  -Q "SET NOCOUNT ON; SELECT CONCAT('UPDATE dbo.CatalogoParametro SET valor = N''', REPLACE(valor, '''', ''''''), ''' WHERE grupo = ''', grupo, ''' AND clave = ''', clave, ''';') FROM dbo.CatalogoParametro WHERE valor <> valorDefecto;" `
  | Set-Content .\parametros_propios.sql -Encoding UTF8
Get-Content .\parametros_propios.sql   # revise la lista (puede estar vacía)
```

Despliegue (indique el contenedor: si `.env` no trae `SQL_CONTAINER_NAME`, el script usa `sqlserver` por defecto):

```powershell
.\deploy_schema.ps1 -ContainerName sql_server_asistencias
```

Tarda varios minutos y debe terminar con `Despliegue del esquema por objeto completado con exito!`. Si `parametros_propios.sql`
no está vacío, repóngalos:

```powershell
docker cp .\parametros_propios.sql sql_server_asistencias:/tmp/parametros_propios.sql
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -b -d gestionasistenciadb -i /tmp/parametros_propios.sql
```

## 8. Comprobar

```powershell
.\scripts\migrar.ps1 -Modo Estado      # esperado: MIGRAR_RESUMEN modo=Estado total=42 registradas=42 pendientes=0 deriva=0
.\scripts\migrar.ps1 -Modo Detectar    # esperado: detectadas=42 ausentes=0 parciales=0 contigua_hasta=42
Remove-Variable pw                     # borra la clave de la sesion
```

## 9. Reiniciar el backend

Inicie el backend como siempre y pruebe una pantalla que use lo nuevo (por ejemplo el plan de estudio del estudiante, HU018, o la
toma de asistencia por puntos de control).

## 10. Volver atrás (si algo salió mal)

Con el backend detenido, restaure el respaldo del paso 2:

```powershell
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -b `
  -Q "ALTER DATABASE [gestionasistenciadb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; RESTORE DATABASE [gestionasistenciadb] FROM DISK = N'$bak' WITH REPLACE, CHECKSUM, STATS = 25; ALTER DATABASE [gestionasistenciadb] SET MULTI_USER;"
```

O con Infra: `..\Repositorio_GestionAsistenciaInfra\infra.ps1 db-reset-qa -Mode Restore -Backup <archivo>.bak -StopBackend -Yes`.

## Nota: intercalación (collation) del servidor

La base y la CI usan `SQL_Latin1_General_CP1_CI_AS`. Un contenedor creado sin `MSSQL_COLLATION` puede quedar con las bases de
sistema (y `tempdb`) en otra intercalación, por ejemplo `Modern_Spanish_CI_AS`. La aplicación funciona igual, pero la compuerta de
pruebas (`test_summary.ps1`) falla con `Cannot resolve the collation conflict` en las pruebas que usan tablas temporales. Consulta:

```powershell
docker exec sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -h -1 -W `
  -Q "SELECT CONVERT(varchar(60), SERVERPROPERTY('Collation')) AS servidor, CONVERT(varchar(60), DATABASEPROPERTYEX('tempdb', 'Collation')) AS tempdb, CONVERT(varchar(60), DATABASEPROPERTYEX('gestionasistenciadb', 'Collation')) AS base;"
```

Si `servidor` o `tempdb` no es `SQL_Latin1_General_CP1_CI_AS`, no hace falta cambiar nada para usar la aplicación ni para este
procedimiento (`migrar.ps1 -Modo Detectar` no usa tablas temporales). Cambiar la intercalación del servidor exige recrear la
instancia; no lo haga sin acordarlo con el equipo.

## Alternativa: base de pruebas de Infra (reemplaza sus datos)

`infra.ps1 db-reset-qa -Mode Base` **reemplaza** la base con el respaldo canónico más el fixture de datos de prueba ampliados: solo
sirve si acepta perder sus datos actuales. Hasta el 2026-11-13 aplicaba un rango fijo de migraciones (13 a 28) y dejaba la base
atrasada; con la rama `fix/VAL-migrar-detectar` de Infra usa `migrar.ps1` (`-Modo Baseline -SoloDetectadas` y `-Modo Aplicar`) y
termina alineada con develop. Si su copia de Infra todavía tiene `MigrationTo = 28` en `scripts/database/reset-datos-prueba.ps1`,
no la use para esto.
