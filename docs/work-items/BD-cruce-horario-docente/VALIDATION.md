---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# VALIDATION — Cruce de horario del docente (opción A)

Validación local (2026-10-29), con una réplica del job "DB Quality Gate" en un contenedor desechable (`asis_dbtest_ci`, sin puerto publicado, que se borra al terminar). La rama ya incluye `develop` con la eliminación de código sin uso (#69).

| Paso | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_EXIT=0`: no se tocó ningún objeto congelado |
| `deploy_schema.ps1` | `SQL_ERROR_COUNT=0` |
| `test_summary.ps1` | `FAILED=0`, `CRITICAL_MISSING=0`, `SUMMARY_EXIT=0`. Ejecutados 369, aprobados 368 y 1 omisión permitida. IDs requeridos: 245 (239 más los 6 nuevos) |
| Suite `test_cruce_horario_docente` | Pasan los 6 escenarios de la matriz del PLAN |
| Inventario | 89 SP públicos (repo = instancia) y 65 vistas |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=131` |

**Hallazgo durante la validación.** La primera corrida falló en `TEACHER_SCHEDULE_OTHER_PERIOD_ALLOWED`. El interno invocaba `usp_validar_grupo_exista_para_docente_interno`, que exige que el grupo esté en el período vigente, así que habría bloqueado cambiar el titular de un grupo de otro semestre. Se quitó esa invocación (ver PLAN) y la segunda corrida pasó completa.

**Backend** (rama `fix/cruce-horario-docente`): `mvnw -B verify` dio 2682 pruebas, 0 fallos y `BUILD SUCCESS`.
