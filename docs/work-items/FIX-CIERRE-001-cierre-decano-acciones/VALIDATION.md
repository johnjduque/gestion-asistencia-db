# FIX-CIERRE-001 (BD): cierre masivo, alta de decano y acciones del docente

Fecha: 2026-11-16. Rama `fix/cierre-masivo-decano-acciones` desde `develop` 6ed9b26. Origen: auditoría de pruebas 2026-11-15
(hallazgos de producción pendientes) y decisiones de producto del responsable del 2026-11-16. Solo cambian cuerpos de
procedimientos (se despliegan con `deploy_schema.ps1`, `CREATE OR ALTER`): no hay migración, tablas, vistas ni mensajes nuevos.

## Reglas

| # | Procedimiento | Regla anterior | Regla nueva |
| :-- | :--- | :--- | :--- |
| 1 | `usp_ejecutar_cierre_masivo_periodo` | Código vacío o que no coincide con ningún periodo: cerraba el periodo más reciente | Sin código (nulo, vacío o espacios) responde `GEN_002`; código que no existe responde `PER_001`. En ambos casos `estadoResultado = 0` y no cierra ni audita nada. Con código válido (nombre o código numérico) cierra ese periodo y solo ese |
| 2 | `usp_crear_decano` | Facultad por nombre con `LIKE '%x%'` y `TOP 1` alfabético; un id inexistente se ignoraba sin avisar | Facultad solo por id o nombre exacto (sin distinguir mayúsculas ni espacios extremos). Facultad indicada (id o nombre) que no existe: `FAC_001`, no se crea el decano. Sin facultad: se crea el decano sin facultad (HU178) |
| 3 | `usp_consultar_revisiones_cancelacion_docente_paginado` | `accionesPermitidas` siempre vacío | Las decisiones del docente que permite el catálogo en el estado actual (`TransicionRevisionCancelacion` con `esDecisionResolutor = 0`, separadas por coma y en orden ascendente, p. ej. `MANTENER,PROPONER`), solo si la matrícula está inscrita; vacío en cualquier otro caso. Es la misma regla de la sábana del docente (`usp_consultar_resumen_asistencia_grupo_docente_paginado`) y de `usp_decidir_revision_cancelacion` |

`esResolutorActual` del listado del docente **sigue en 0**: la columna significa "es resolutor de esta revisión" (coordinador,
`ufn_revision_cancelacion_resolutores`), el docente nunca resuelve (DEC-065) y el cliente del docente no la usa. Decidir otra
semántica ("es quien debe actuar ahora") es una decisión de producto que no se puede derivar del código.

Mensajes reutilizados del catálogo (sin altas): `GEN_002`, `PER_001`, `FAC_001`.

## Pruebas

| Archivo | Casos | RED sobre el código anterior |
| :--- | :--- | :--- |
| `test/test_fix_cierre_001_cierre_masivo.sql` (nuevo) | `FIX001_CIE_01` código inexistente; `_02` nulo, vacío y espacios; `_03` válido por nombre y por código numérico (audita su id y no toca otras matrículas) | `CIE_01` falla con el SP anterior (cerraba el periodo más reciente) |
| `test/test_fix_cierre_001_decano.sql` (nuevo) | `FIX001_DEC_01` nombre aproximado; `_02` comodín `%`; `_03` nombre inexistente; `_04` id inexistente; `_05` nombre exacto con otra capitalización; `_06` id existente; `_07` sin facultad | `DEC_01` falla con el SP anterior |
| `test/test_culm001_c_revisiones.sql` (C-DB-35, actualizado) | acciones del docente contra el catálogo, `PROPUESTA` sin acciones, `PENDIENTE_DOCENTE` con matrícula inscrita = `MANTENER,PROPONER`, matrícula no inscrita sin acciones | falla con el SP anterior (acciones vacías) |

Prueba existente actualizada por cambio formal de regla: `test/test_culm001_c_revisiones.sql`, aserción C-DB-35 (antes línea 309)
exigía `accionesPermitidas <> N''` como falla; ahora el docente recibe acciones (ver regla 3). `esResolutorActual <> 0` se conserva.
Ninguna otra prueba afirmaba el comportamiento anterior: todas las que llaman al cierre masivo pasan un código válido.

Registro: `test_suite.sql` (dos `:r`) y `test_summary.ps1` (`FIX001_*` en la lista de ids críticos).
Manifiesto: `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` (hash de `usp_crear_decano.sql`).

## Evidencia (contenedor SQL Server 2022 desechable `sql_gate_fix001`, base creada con `deploy_schema.ps1`; la BD del laboratorio no se tocó)

| Paso | Resultado |
| :--- | :--- |
| Pruebas nuevas y C-DB-35 contra los SP anteriores | `TEST FAILED` en `FIX001_CIE_01`, `FIX001_DEC_01` y C-DB-35 (RED) |
| Mismas pruebas con los SP nuevos | `TEST_PASS` de los 12 ids `FIX001_*` y de `CULM001_C_REVISIONES` (GREEN) |
| `test_suite.sql` completo (sin `test_culm001_b2_tomas.sql`), con fixture LB-004D | `SUITE_EXIT=0` |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK` |

## No verificado localmente

- `test_culm001_b2_tomas.sql` (`CULM001_B2_TOM_06`, cierre de toma QR) falló en el contenedor local; no toca los procedimientos de este
  cambio y se excluyó para poder ejecutar el resto de la suite. No se comprobó si falla también sobre `develop` sin este cambio.
- `test_val_migrar_detectar.ps1` no corre en esta máquina Windows (`tar` de Git no acepta rutas `C:`).
- Compuerta completa (`test_summary.ps1` con los 684 ids): queda para el CI del PR.
