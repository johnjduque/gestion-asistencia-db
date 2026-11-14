---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-migrar-detectar (BD) - VALIDATION

Fecha: 2026-11-13. Rama `fix/VAL-migrar-detectar` sobre `origin/develop` 5c4f30c.

Entorno: contenedor desechable `mcr.microsoft.com/mssql/server:2022-latest` con `MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS`,
clave aleatoria generada en la corrida (no se imprimió) y límite de 2.5 GB de memoria; se borró al terminar. Contra
`sql_server_asistencias` solo se ejecutó `-Modo Detectar` (solo lectura) y se copió fuera, sin modificarlo, un respaldo existente.

## 1. Efecto real de cada migración (fotos del catálogo)

Base con el `schema/` del commit `8f18b76` (develop antes de la 17), `Baseline -HastaVersion 16` y luego `Aplicar -HastaVersion N`
para cada N de 17 a 42, con foto del catálogo tras cada paso. Las 25 migraciones se aplicaron sin error. Evaluación de los marcadores
contra las fotos (D = APLICADA_DETECTADA, A = AUSENTE; nunca salió P = PARCIAL):

| Migración | estado 16 | paso 17 ... paso N-1 | paso N en adelante y despliegue limpio |
| :--- | :--- | :--- | :--- |
| 05..16 (17 migraciones) | D | D | D |
| 17, 18, 19, 21..34, 37..42 | A | A | D (cambia exactamente en su paso) |
| 20 | D (ya estaba en el esquema de esa fecha) | D | D |
| 36 (solo retiro) | D | D | D |

## 2. Ensayo del runbook (`docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md`)

Copia del estado 16 restaurada como `gestionasistenciadb` en el contenedor desechable; comandos con los valores por defecto (la
ruta real, sin cambio de nombre de base):

| Paso | Resultado |
| :--- | :--- |
| `-Modo Detectar` | `detectadas=19 ausentes=23 parciales=0 sin_marcadores=0 contigua_hasta=16`; 20 y 36 `fuera_de_orden=1` |
| `-Modo Baseline -SoloDetectadas` | 17 registradas `BASELINE` (05..16); 20 y 36 `MIGRAR_DETECTADA_FUERA_DE_ORDEN` |
| `-Modo Aplicar` | 25 aplicadas en orden (17, 18, 19, 20, 21 ... 42); `pendientes=0 deriva=0` |
| `-Modo Estado` | `total=42 registradas=42 pendientes=0 deriva=0` |
| `deploy_schema.ps1` | terminó bien |
| `-Modo Estado` / `-Modo Detectar` | `pendientes=0 deriva=0` / `detectadas=42 ... contigua_hasta=42` |

Tiempo total del ensayo: unos 5 minutos.

Comparación con un despliegue limpio del `schema/` actual (tablas, columnas, índices, restricciones, hash de cada módulo, permisos
del rol de runtime y filas de catálogo):

- Solo con las migraciones (antes de `deploy_schema.ps1`): faltaban 6 SP (`usp_consultar_alertas_estudiante`,
  `usp_consultar_audiencias_realtime_grupo`, `usp_consultar_destinatarios_revision_cancelacion`,
  `usp_consultar_grupos_pendientes_evaluacion_alertas`, `usp_consultar_revisiones_cancelacion_coordinador_paginado`,
  `usp_evaluar_alertas_inasistencia_grupo`), 10 `GRANT EXECUTE`, 22 mensajes `ALR_*`/`RCN_*` (usuario y técnico), 8 parámetros,
  4 plantillas con 25 marcadores, y 2 SP con la versión anterior (`usp_ejecutar_cierre_masivo_periodo` y
  `usp_consultar_resumen_asistencia_grupo_docente_paginado`, los que nombra el encabezado de la 19). Otros 65 módulos solo cambiaron
  comentarios o espacios. Es lo que las migraciones dejan a `deploy_schema.ps1` según sus encabezados.
- Después de `deploy_schema.ps1`: igual al despliegue limpio salvo la tabla de reporte `zz_reporte_culm001_b2nm_estudiante_programa`
  (la crea la 17 a propósito). Por eso el paso de `deploy_schema.ps1` es obligatorio en el runbook.

## 3. Respaldo real del 2026-11-09 (base mantenida con `deploy_schema.ps1`)

`gestionasistenciadb_pre_culm001_20261109.bak` (copiado de `sql_server_asistencias` sin modificarlo) restaurado como
`gestionasistenciadb_qa`:

- `Detectar`: `detectadas=10 ausentes=29 parciales=3`: 05 hu091 (sigue `usp_registrar_docente_en_grupo_autonomo`), 13 (1/11) y 14
  (2/7: existe `Decano` sin la columna `estado`). `-SoloDetectadas` se detuvo sin registrar nada, como se espera.
- `Aplicar` sobre esa base sin registrar nada: las 42 se ejecutaron sin error; después `Detectar`: `detectadas=42`. Las 05..16 son
  idempotentes en esa base.
- Infra `reset-datos-prueba.ps1 -Mode Base` con ese respaldo (rama `fix/VAL-migrar-detectar` de Infra): `-ReaplicarParciales`,
  42 aplicadas, `pendientes=0 deriva=0`, `deploy_schema.ps1`, fixture y 11 `TEST_PASS:QA_DATOS_*`.

## 4. Base de desarrollo `gestionasistenciadb` (`sql_server_asistencias`), solo lectura

```
.\scripts\migrar.ps1 -Modo Detectar
MIGRAR_DETECTAR_BASE gestionasistenciadb registro=presente (Detectar no lo usa ni lo modifica)
MIGRAR_DETECTAR_RESUMEN total=42 detectadas=42 ausentes=0 parciales=0 sin_marcadores=0 contigua_hasta=42 (42_val_mensajes_err_pendientes)
```

## 5. Pruebas

`test/test_val_migrar_detectar.ps1` (nuevo) y `test/test_val_migrar.ps1` (existente) contra el contenedor desechable:

```
TEST_PASS:VAL_MDET_01_MARCADORES_COMPLETOS
TEST_PASS:VAL_MDET_02_DESPLIEGUE_LIMPIO_TODAS
TEST_PASS:VAL_MDET_03_ESTADO_16_CLASIFICA
TEST_PASS:VAL_MDET_04_PARCIAL_BLOQUEA
TEST_PASS:VAL_MDET_08_REAPLICAR_PARCIALES
TEST_PASS:VAL_MDET_05_SOLO_DETECTADAS_REGISTRA
TEST_PASS:VAL_MDET_06_APLICAR_EN_ORDEN
TEST_PASS:VAL_MDET_07_TRAS_APLICAR_TODAS
TEST_PASS:VAL_F1212_01_ESTADO_SOLO_LECTURA ... TEST_PASS:VAL_F1212_07_INVENTARIO_REAL (7/7)
```

La prueba nueva tarda unos 10 a 14 minutos (dos despliegues completos y 25 migraciones) y necesita la historia de develop
(`fetch-depth: 0`, ya configurado en la CI) para leer el `schema/` del commit `8f18b76`. No se corrió `test_summary.ps1` completo.

## 6. Manifiestos

```
.\scripts\freeze-manifest.ps1 -Mode UpdateCulm001D -Paths scripts/migrar.ps1,scripts/migrar-marcadores.json
.\scripts\freeze-manifest.ps1 -Mode Verify   -> FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11 culm001_d=86
.\scripts\lb004d-manifest.ps1 -Mode Verify   -> LB004D_MANIFEST_OK entries=9
```

## 7. Hallazgos durante la validación

- `sqlcmd -W` y `-y 0` son incompatibles; `Detectar` usa `-W` con salidas cortas (`<n>|0/1`).
- Al reescribir el nombre de la base en copias de `.sql` hay que conservar la marca BOM: sin ella `sqlcmd` lee el archivo con otra
  página de códigos y cambia las tildes (lo hace `Copy-ConBaseCambiada` en `migrar.ps1` y el despliegue de la prueba).
- En PowerShell, el `-match` dentro de una expresión reescribe `$Matches` antes de usarlo como índice (corregido en la prueba).
