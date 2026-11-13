---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-oleada3-bd-pendientes (BD) - PLAN

Fecha: 2026-11-13. Rama `fix/VAL-oleada3-bd-pendientes`, creada desde `origin/develop` (86dc810).
Ítems de `informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`: PRU-14, OBS-03, F12-12 y PRU-05.

Sin migración nueva: no se cambia ningún procedimiento, vista ni función existente. Lo único nuevo en `schema/` es la tabla
`dbo.MigracionAplicada`, que despliega `deploy_schema.ps1` y que `scripts/migrar.ps1` crea si falta. Por eso esta rama no
depende de `fix/VAL-oleada3-mensajes-catalogo` (migración 41) ni de `fix/VAL-oleada3-pru04-cuarentena`. Cuando la 41 se una,
la tarea de migración la verá como `PENDIENTE` en las bases que la registraron hasta la 40.

| Ítem | Cambio | Archivo |
| :--- | :--- | :--- |
| PRU-14 | Pruebas de borde del umbral de horas | `test/test_val_umbral_horas_bordes.sql` |
| OBS-03 | Clasificación de los 17 procedimientos sin `@idCorrelacion` y compuerta que falla si aparece uno nuevo sin entrada en la lista blanca | `test/test_val_obs03_id_correlacion.sql` |
| F12-12 | Tabla de migraciones aplicadas, tarea de migración y su prueba; la CI registra la línea base tras desplegar | `schema/tables/MigracionAplicada.sql`, `scripts/migrar.ps1`, `test/test_val_migrar.ps1`, `.github/workflows/ci.yml` |
| PRU-05 | Resumen saneado de la compuerta de BD | `docs/work-items/VAL-oleada3-bd-pendientes/VALIDATION.md` |
| Registro | Ids en `test_suite.sql` y `test_summary.ps1`; `MigracionAplicada.sql` y `migrar.ps1` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | |

## PRU-14: bordes del umbral de horas

La regla vive en `dbo.ufn_calcular_porcentaje_inasistencia_horas` (porcentaje por horas, `ROUND` a 2 decimales, acotado a
[0, 100]) y `dbo.ufn_clasificar_permanencia` (REGULAR < `UMBRAL_ALERTA_ADVERTENCIA` <= RIESGO < `UMBRAL_ALERTA_PERDIDA` <=
PERDIDA). El motor de alertas y el cierre leen el umbral con `dbo.ufn_umbral_alerta_inasistencia`. Antes solo se probaban
15.00 y 20.00 con el fixture de horas (`CULM001_B2_HOR_05`).

| Id | Qué prueba |
| :--- | :--- |
| `VAL_PRU14_01_PORCENTAJE_FRONTERA` | 19.99 / 20.00 / 20.01 sobre 100 h y sobre horas fraccionarias (9.595 / 9.6 / 9.605 de 48 h); redondeo 19.994 -> 19.99 y 19.995 -> 20.00; cero, NULL y negativos -> 0.00 |
| `VAL_PRU14_02_CLASIFICACION_FRONTERA` | Con umbrales fijados en 15 y 20: 14.99 REGULAR, 15.00 y 15.01 RIESGO, 19.99 RIESGO, 20.00 y 20.01 PERDIDA, 0 REGULAR, 100 PERDIDA, `CI` siempre PERDIDA, porcentaje NULL REGULAR; cadena horas -> porcentaje -> clase; el umbral de alertas lee el mismo parámetro |
| `VAL_PRU14_03_PARAMETRO_AUSENTE` | Parámetro inactivo, vacío, no numérico o sin fila: la clasificación y el umbral de alertas devuelven NULL (nunca asumen un valor) |
| `VAL_PRU14_04_MAXIMO` | Falta igual o mayor que lo dictado -> 100.00; extremos de `DECIMAL(12,6)` sin desbordamiento; PERDIDA en su máximo editable (100): 99.99 RIESGO y 100.00 PERDIDA; el rango editable sigue en 1..100 |
| `VAL_PRU14_05_VISTA_MISMA_REGLA` | Cada fila de `uv_resumen_asistencia_estudiante_grupo` tiene el porcentaje y la clase que dan las dos funciones (no hay regla paralela) |
| `VAL_PRU14_TRANCOUNT_ZERO` | Sin transacción abierta al final |

Los casos que cambian parámetros lo hacen dentro de una transacción que siempre se revierte. Sin fixture nuevo: las fronteras
son de funciones puras y la integración con datos ya la cubre `test_culm001_b2_horas.sql`.

Hallazgos (comportamiento vigente, documentado, no se cambia aquí):

- El redondeo a 2 decimales ocurre antes de comparar: 19.995 % se muestra 20.00 y ya es PERDIDA. Si se quiere comparar sin
  redondear, es una decisión de negocio.
- `CatalogoParametro.valor` es `NOT NULL`, así que `ISNULL(valor, valorDefecto)` nunca usa el valor por defecto: con
  `valor = ''` la regla devuelve NULL aunque `valorDefecto` sea válido.
- El frontend (Sergio) sigue sin casos de borde; PRU-14 queda cumplido en la parte de BD.

## OBS-03: procedimientos sin `@idCorrelacion`

Conteo real (2026-11-13): 280 archivos en `schema/stored-procedures`; 263 declaran `@idCorrelacion` en sus parámetros y 17 no.
La base de desarrollo da los mismos 17 (`sys.parameters`). La lista de chequeo decía 18 de 339 porque contaba todos los
archivos del repo con `CREATE PROCEDURE`, incluido el fixture `test/fixtures/culm001_b2_toma_fixture.sql` (procedimientos
temporales de la sesión de prueba). Ninguno de los 17 necesita el parámetro, así que no se cambia ninguna firma.

| Procedimiento | Clase | Por qué no lo necesita |
| :--- | :--- | :--- |
| `usp_actualizar_nombres_usuario_interno` | NUCLEO_MUTANTE | Núcleo sin EXECUTE para la app; solo lo llama `usp_actualizar_docente_programa`, que recibe `@idCorrelacion` y audita |
| `usp_internal_marcar_ausentes_toma` | NUCLEO_MUTANTE | Núcleo sin EXECUTE; corre dentro de la transacción de `usp_cerrar_toma_asistencia` / `usp_cerrar_tomas_vencidas`, que llevan la correlación |
| `usp_internal_resolver_token_matricula` | NUCLEO_MUTANTE | Núcleo sin EXECUTE; solo marca EXPIRADA una ventana vencida dentro de la transacción de `usp_internal_matricular_por_token` / `usp_validar_token_matricula_publico` |
| `usp_establecer_contexto_usuario_ejecutor` | CONTEXTO_SESION | Solo fija `SESSION_CONTEXT`; no escribe tablas; lo usan los procedimientos que ya llevan la correlación |
| `usp_internal_resolver_token_asistencia` | LECTURA | Resuelve token o PIN sin escribir; lo llama `usp_registrar_asistencia_por_token` |
| `usp_consultar_contacto_notificacion_interno` | LECTURA | Consulta interna de su fachada pública (con correlación) |
| `usp_consultar_notificaciones_salientes_admin_interno` | LECTURA | Consulta interna de su fachada pública |
| `usp_consultar_plantilla_notificacion_activa_interno` | LECTURA | Consulta interna de su fachada pública |
| `usp_consultar_plantillas_notificacion_admin_interno` | LECTURA | Consulta interna de su fachada pública |
| `usp_consultar_ventanas_matricula_por_rotar` | LECTURA | Público solo para el job de rotación del backend; sin ejecutor ni datos personales; la correlación del job vive en sus logs |
| `usp_obtener_mensaje_catalogo` | LECTURA | Lee el catálogo de mensajes; el llamador arma la salida con su propia correlación |
| `usp_resolver_periodo_kpi_interno`, `_facultad_interno`, `_institucion_interno` | LECTURA | Resuelven el periodo de un KPI dentro de consultas que llevan la correlación |
| `usp_validar_estudiante_en_programa_interno`, `usp_validar_programa_en_facultad_interno`, `usp_validar_id_interno` | LECTURA | Validaciones de solo lectura que devuelven el mensaje al llamador |

Compuerta automática (`test/test_val_obs03_id_correlacion.sql`, contra el catálogo del motor):

| Id | Qué comprueba |
| :--- | :--- |
| `VAL_OBS03_01_SIN_CORRELACION_EN_LISTA` | Todo procedimiento de `dbo` sin `@idCorrelacion` está en la lista blanca. Uno nuevo, mutante o no, sin el parámetro y sin entrada, hace fallar la compuerta |
| `VAL_OBS03_02_LISTA_SIN_ENTRADAS_VIEJAS` | Cada entrada existe y sigue sin el parámetro (si se le agrega, se saca de la lista) |
| `VAL_OBS03_03_LECTURA_NO_ESCRIBE` | Las entradas LECTURA y CONTEXTO_SESION no actualizan tablas (`sys.dm_sql_referenced_entities.is_updated`) |
| `VAL_OBS03_04_NUCLEOS_SIN_EXECUTE_Y_CON_LLAMADOR` | Los NUCLEO_MUTANTE no tienen EXECUTE para `rol_asistencias_runtime` y tienen un llamador que sí declara `@idCorrelacion` |

Para agregar una excepción: entrada en `#obs03Lista` del test con su clase y una fila en esta tabla con la razón.

## F12-12: registro de migraciones y tarea de migración

Antes no existía nada parecido: ni tabla de versiones ni ejecutor (las migraciones se aplicaban a mano con `sqlcmd`).

- `dbo.MigracionAplicada`: `version` (prefijo numérico), `nombre` (archivo sin `_up.sql`; clave única porque hay números
  repetidos: 05, 06, 07, 08 y 11), `archivo`, `checksumSha256` (CRLF normalizado a LF, como los manifiestos), `modo`
  (`APLICADA` o `BASELINE`), `aplicadaEnUtc`, `aplicadaPor`, `duracionMs`. Sin permisos para la app.
- `scripts/migrar.ps1`:
  - `-Modo Estado` (por defecto, solo lectura): `MIGRAR_APLICADA`, `MIGRAR_BASELINE`, `MIGRAR_PENDIENTE` o `MIGRAR_DERIVA` por
    migración y `MIGRAR_RESUMEN`.
  - `-Modo Aplicar`: crea la tabla si falta, aplica las pendientes en orden (versión, nombre) con `sqlcmd -b`, `MIGDIR` y
    `schema/` copiados al contenedor, y registra cada una al terminar bien. Se salta las ya registradas. Se detiene en la
    primera que falla (no la registra) y antes de aplicar nada si un archivo ya aplicado cambió (deriva).
  - `-Modo Baseline [-HastaVersion N]`: registra sin ejecutar. Es para una base creada con `deploy_schema.ps1`, que ya contiene
    el efecto de todas las migraciones.
  - Administra `NN_nombre_up.sql` y los antiguos de un solo archivo con NN >= 5. Los `_down.sql` no se aplican; para revertir:
    ejecutar el down a mano y borrar la fila. 01..04 son cargas anteriores al esquema por objeto.
  - Credenciales como `deploy_schema.ps1` (parámetro o `.env`); nunca se imprimen.
- CI: después de `deploy_schema.ps1`, `migrar.ps1 -Modo Baseline` y `-Modo Estado` deben terminar con `pendientes=0 deriva=0`.

Uso en una base existente (dev o laboratorio):

```powershell
.\scripts\migrar.ps1                                   # ver estado
.\scripts\migrar.ps1 -Modo Baseline -HastaVersion 40   # una sola vez, si la base ya tiene aplicadas hasta la 40
.\scripts\migrar.ps1 -Modo Aplicar                     # aplicar lo nuevo (p. ej. la 41 cuando se una)
```

Prueba (`test/test_val_migrar.ps1`, base temporal `qa_migrar_<tag>` y migraciones sintéticas; nunca toca
`gestionasistenciadb`): `VAL_F1212_01_ESTADO_SOLO_LECTURA`, `_02_APLICA_Y_REGISTRA`, `_03_SALTA_APLICADAS`,
`_04_FALLA_NO_REGISTRA`, `_05_DERIVA_DETIENE`, `_06_BASELINE_SIN_EJECUTAR` y `_07_INVENTARIO_REAL` (lee las 40 migraciones
reales sin ejecutarlas).

Límites: la migración y su fila no van en una sola transacción (las migraciones tienen varios lotes `GO` y su propia
transacción). Si la migración termina y la inserción de la fila falla, la siguiente corrida la reaplica; las migraciones del
repo son idempotentes. No hay bloqueo contra dos operadores a la vez: la tarea la corre una sola persona o la CI.

## PRU-05

Se corre la compuerta de BD completa (`deploy_schema.ps1` y `test_summary.ps1`) sin ningún build de Maven en paralelo y se
guarda el resumen saneado (conteos, resultado, fecha y commit, sin credenciales) en `VALIDATION.md`.
