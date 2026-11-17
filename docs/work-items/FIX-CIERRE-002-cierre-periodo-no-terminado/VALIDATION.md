# FIX-CIERRE-002 (BD): el cierre masivo solo se ejecuta sobre un período que ya terminó

Fecha: 2026-11-17. Rama `fix/cierre-masivo-periodo-no-terminado` desde `develop` deec79f. Origen: decisión del responsable del
2026-11-17. El cierre masivo (`usp_ejecutar_cierre_masivo_periodo`) sigue siendo MANUAL (lo ejecuta el administrador con advertencia
y confirmación); no se automatiza.

## Regla

| # | Procedimiento | Regla anterior | Regla nueva |
| :-- | :--- | :--- | :--- |
| 1 | `usp_ejecutar_cierre_masivo_periodo` | No comprobaba fechas: un administrador podía cerrar el período vigente a mitad de semestre | Solo cierra un período ya terminado. Si el período existe pero aún no terminó (en planeación o vigente) responde `estadoResultado = 0` con `PER_007` (texto con su fecha de fin, `dd/MM/yyyy`) sin cerrar ni auditar nada y antes de abrir la transacción de cierre |

"Terminó" usa el mismo criterio que la columna `estado` de `uv_periodo_academico`: fecha local institucional
(`TIEMPO/ZONA_HORARIA_SQLSERVER`) estrictamente posterior a `fechaFin` equivale a `CERRADO`. El día exacto de `fechaFin` cuenta como
NO terminado. El SP reutiliza la vista (ya la consultaba para resolver el período) y no duplica el cálculo de la fecha.

Orden de validaciones: correlación, perfil ADMINISTRADOR, código de período indicado (`GEN_002`), período existe (`PER_001`),
**período terminado (`PER_007`, nuevo)**, ejecución.

## Mensaje nuevo

`PER_007` (`BUSINESS_ERROR`, `MEDIO`), semilla `schema/seed/17_mensajes_periodo_academico.sql` (usuario y técnico):

> El período académico aún no ha finalizado; el cierre masivo solo puede ejecutarse después de su fecha de fin ({}).

Migración `migrations/48_fix_cierre_periodo_no_terminado_up.sql` (y `_down`) lleva el mensaje a bases existentes (mismo patrón que la
47); el cuerpo del SP se despliega con `deploy_schema.ps1` (`CREATE OR ALTER`). Marcador en `scripts/migrar-marcadores.json`
(`dbo.CatalogoMensajeUsuario` con `codigo = 'PER_007'`) y manifiesto `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` actualizado con
`freeze-manifest.ps1 -Mode UpdateCulm001D`.

## Pruebas

| Archivo | Casos | RED sobre el SP anterior |
| :--- | :--- | :--- |
| `test/test_fix_cierre_002_periodo_no_terminado.sql` (nuevo) | `FIX002_CIE_01` período vigente; `_02` período en planeación; `_03` el día exacto de `fechaFin` (frontera); `_04` período con `fechaFin` ayer sigue cerrando ese período y solo ese (A a F, contador, auditoría con su id); `_05` `@@TRANCOUNT = 0` | `TEST FAILED FIX002_CIE_01-03` con el SP anterior (cerraba el período vigente) |

Cada rechazo comprueba: una sola fila, `estadoResultado = 0`, `DBCODE=PER_007`, el texto con la fecha de fin, matrícula y contador
del grupo sin cambios, ningún `AuditoriaEvento` nuevo y la transacción de la prueba intacta.

Pruebas existentes: ninguna requirió ajuste. Las que ejecutan el cierre (`test_culm001_c_cierre_masivo`, `test_mass_period_close`,
`test_rec3_falla_intermedia_transaccion` TX-03 y `test_fix_cierre_001_cierre_masivo`) ya preparaban períodos con `fechaFin` en el
pasado; las dos de migraciones solo comparan definiciones.

Registro: `test_suite.sql` (un `:r`) y `test_summary.ps1` (ids `FIX002_*`).

## Idempotencia (solo observado, sin cambios)

Cerrar dos veces el mismo período ya terminado: la segunda llamada responde `exitoso = 1` (`GEN_004`), no encuentra matrículas
inscritas (0 `A -> F`), recalcula los contadores del grupo (mismos valores) y escribe OTRO `AuditoriaEvento` `CIERRE_MASIVO_PERIODO`
con `finalizados = 0`. No se rechaza ni se deduplica.

## Documentación

`docs/catalogos/catalogo-mensajes.md` (fila `PER_007`, total 486), `docs/arquitectura/especificacion_sp_endpoints.md` (descripción del
SP) y `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` (rango `PER_001`..`PER_007`).

## Evidencia (contenedor SQL Server 2022 desechable `sql_gate_cie2`; la BD del laboratorio no se tocó)

Ver el cuerpo del PR: despliegue desde cero, fixture LB-004D, `test_summary.ps1`, `freeze-manifest.ps1 -Mode Verify` y
`migrar.ps1` Detectar/Baseline/Estado.
