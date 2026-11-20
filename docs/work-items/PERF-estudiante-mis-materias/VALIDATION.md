---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# VALIDATION — PERF-EST-MM

Base local de desarrollo (`sql_server_asistencias`), 2026-11-19.

| Paso | Resultado |
|---|---|
| Respaldo previo | `respaldos-bd/gestionasistenciadb_2026-11-19_antes-migracion59.bak` (`BACKUP ... COPY_ONLY, CHECKSUM`) |
| `scripts/migrar.ps1` (estado) | 58 registradas, 1 pendiente (59), deriva 0 |
| `scripts/migrar.ps1 -Modo Aplicar` | `MIGRAR_APLICADA_AHORA 59_perf_estudiante_mis_materias` |
| SP antes / después | `usp_consultar_sesiones_materia_estudiante` para cada estudiante y materia con sesiones, páginas 1..3 de 2 filas: salida idéntica (`diff` vacío) |
| Vistas antes / después | `uv_sesion_estudiante_reclamo` (todas las columnas) y `uv_asistencia_toma_estudiante` (`esReclamable`, solicitud, estado): idénticas |
| `test/test_perf_estudiante_mis_materias.sql` | `PERF_MM_01`..`PERF_MM_06` en TEST_PASS |
| `migrations/59_*` con `SET PARSEONLY ON` | up y down sin errores de sintaxis |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK` |
| Búsqueda del término prohibido por `AULA_ACTIVE_SQL_REFERENCES_ZERO` | 0 coincidencias en los archivos nuevos o cambiados |

No se corrió localmente la suite completa (`test_summary.ps1`) ni las pruebas lentas de detección de migraciones: quedan para CI.
