---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-11
---

# VALIDATION — PC: tomas de asistencia como puntos de control

Contrato: [CONTRACT.md](CONTRACT.md). Plan: [PLAN.md](PLAN.md). Pruebas: [TEST_PLAN.md](TEST_PLAN.md).

## Compuerta limpia

Base desechable (contenedor nuevo, `deploy_schema.ps1` + `test_summary.ps1`) sobre la rama `feature/PC-tomas-puntos-control` sin commit (BD-1 a BD-4).

| Fecha | Resultado |
|---|---|
| 2026-11-11 (corrida 1) | `DB GATE INCOMPLETE`: `test_pc_puntos_control.sql` reutilizaba el nombre de tabla temporal `#pcC` de `test_pc_calculo_tramos.sql` en la misma sesión (Msg 2714). Se renombraron sus temporales a `#ptc*`. Todas las demás pruebas pasaron, incluidas `PC_SEG_01`, `PC_MIG_01/02` y las migraciones componibles que ahora bajan la 37. |
| 2026-11-11 (corrida 2) | `DEPLOY_EXIT=0`, `FIXTURE_EXIT=0`, `TEST_EXIT=0`; `TOTAL_EXPECTED=600`, `TOTAL_EXECUTED=778`, `PASSED=777`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, **`DB GATE PASS`**. |

## Manifiestos y catálogo

| Comprobación | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11 culm001_d=67` (tras `-Mode UpdateCulm001D -Paths schema/tables/zz_foreign_keys.sql,schema/stored-procedures/usp_internal_radicar_solicitud_revision.sql`) |
| `scripts/lb004d-manifest.ps1 -Mode Verify` | `LB004D_MANIFEST_OK entries=9` |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=291` |

## Migración 37 en la base local

`migrations/37_pc_tomas_puntos_control_up.sql` aplicada el 2026-11-11 en `sql_server_asistencias` (`MIGRACION 37 UP OK`, sin errores). Estado resultante: tope `MAXIMO_TOMAS_POR_SESION` = 20 (valor y valor por defecto), MANUAL con `marcaAusentesAlCerrar = 1`, los 5 mensajes nuevos, las 3 vistas y los 2 SP nuevos, y las columnas `toma` / `razonCausaResolucion`. La prueba `test_pc_migracion_37.ps1` (up→down→up y down sin confirmación) pasó también contra esta base.

## Impacto en datos (foto antes/después)

Foto de `uv_resumen_asistencia_estudiante_grupo` en la base local (`sql_server_asistencias`, datos semilla: 8 cabeceras, 7 tomas en 4 sesiones). "Antes" = vistas de `develop` aplicadas dentro de una transacción revertida; "después" = vistas de PC.

| Matrícula | % inasistencia antes → después | Permanencia | Horas asistidas | Horas de falta | Horas de excusa | Horas sin registro |
|---|---|---|---|---|---|---|
| `B1A2C3D4-…-000000000001` | 38,12 → 71,29 | PERDIDA → PERDIDA | 1,327778 → 1,366667 | 2,655555 → 4,966666 | 1,000000 → 0,633333 | 1,983333 → 0,000000 |
| la otra matrícula con resumen | sin cambio | sin cambio | sin cambio | sin cambio | sin cambio | sin cambio |

La matrícula que cambia tiene dos sesiones con varias tomas: en la de 59 min con marcas SJC/AN/SJC (tomas a los minutos 15, 15 y 23) todos los tramos tocan una SJC y la sesión pasa de 2/3 de falta a falta completa; en la de 2 h con EX/AN (tomas a los minutos 38 y 38) el tramo inicial queda excusado y el resto presente. Es el efecto esperado de la regla (riesgos F2/F3 del diseño). Antes de desplegar en un ambiente con datos reales hay que repetir esta foto en una copia (`idEstudianteGrupo`, `porcentajeInasistencia`, `codigoPermanencia` con las vistas de `develop` dentro de una transacción revertida y con las de PC; diseño §B.3) para dimensionar alertas nuevas y revisiones de cancelación (decisión F2 pendiente de John).

## Revisión en pantalla (2026-11-12)

Un agente QA probó la rama `feature/PC-tomas-puntos-control` en pantalla con la BD migrada (migración 37), el backend en 8080 y el frontend en 4200, con los usuarios `uco-docente` y `uco-estudiante`. Reporte completo: `informes/REVISION_PANTALLA_PUNTOS_CONTROL_2026-11-12.md`.

- Pasan: punto de control y minutos de tramo por toma, toma cerrada no editable tras abrir la siguiente, plazo de la última toma (fin más 30 minutos), aviso al cerrar, resumen de la sesión coincidente con `uv_asistencia_sesion_horas`, estado "Parcial: 34 de 60 minutos", botón de reclamo solo en la toma ausente, radicación del reclamo por toma (202), "Reclamo pendiente", aprobación "Estuvo presente" con recálculo a 60 de 60 minutos, y el resultado visible para el estudiante.
- Hallazgo menor: la bandeja de reclamos del docente no muestra la toma en la tarjeta (solo en el detalle), porque el listado no envía los campos de toma.
- Sin probar: tope de 20 tomas, `TOM_012` y `ERR_RECLAMO_TOMA_DUPLICADO` por API, "Ausencia justificada" y "Rechazar" sobre un reclamo de toma, "Marcar faltantes", QR con cámara y sesión cancelada con tomas.
