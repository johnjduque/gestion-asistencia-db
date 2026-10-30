---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# VALIDATION — Eliminar código sin uso de la BD

Validación local (2026-10-29), con una réplica del job "DB Quality Gate" en un contenedor desechable (`asis_dbtest_ci`, sin puerto publicado, que se borra al terminar). No se tocó `sql_server_asistencias`.

| Paso | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_EXIT=0`: ningún archivo congelado cambió |
| `deploy_schema.ps1` | Sin errores (`SQL_ERROR_COUNT=0`) |
| `test_summary.ps1` | `FAILED=0`, `CRITICAL_MISSING=0`, `SUMMARY_EXIT=0`. Ejecutados 363, aprobados 362 y 1 omisión permitida (`XACT_STATE_MINUS_ONE_RUNTIME`). IDs requeridos: 239 (antes 245, salen los 6 de los objetos eliminados) |
| Inventario | `REPO_PUBLIC_SP_COUNT=89` = `INSTANCE_PUBLIC_SP_COUNT=89`; vistas 65 = 65 |
| Migración 08 | Después del despliegue los 18 objetos no existen (`0`). `_down` los recrea (`18`, exit 0). `_up` los borra (`0`, exit 0), y una segunda ejecución de `_up` también termina en `0` con exit 0, es decir, es idempotente |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=131`: el seed de mensajes no cambió |

Referencia antes del cambio (`develop` con HU025): 386 ejecutados, 385 aprobados y 245 requeridos. La diferencia corresponde a las suites y bloques eliminados.
