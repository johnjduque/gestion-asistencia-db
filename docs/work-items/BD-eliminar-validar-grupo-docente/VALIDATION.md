---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-30
---

# VALIDATION — Eliminar `usp_validar_grupo_exista_para_docente_interno`

Validación local (2026-10-30), con una réplica del job "DB Quality Gate" en un contenedor desechable (`asis_dbtest_ci`, sin puerto publicado, que se borra al terminar).

| Paso | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_EXIT=0` |
| `deploy_schema.ps1` | `SQL_ERROR_COUNT=0` |
| `test_summary.ps1` | `FAILED=0`, `CRITICAL_MISSING=0`, `SUMMARY_EXIT=0`. Ejecutados 369, aprobados 368 y 1 omisión permitida. Requeridos: 245, igual que `develop` |
| Inventario | 89 SP públicos y 65 vistas (repo = instancia) |
| Migración 09 | Después del despliegue el SP no existe (`0`). `_down` lo recrea (`1`, exit 0). `_up` lo borra (`0`, exit 0), y una segunda ejecución de `_up` también termina en `0` con exit 0, es decir, es idempotente |
