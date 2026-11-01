---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-01
---

# VALIDATION — F1: guardar el horario semanal del grupo

## 1. Gate completo en una BD nueva (réplica del CI, 2026-11-01)

Réplica del job "DB Quality Gate" en un contenedor desechable (`asis_dbtest_ci`, SQL Server 2022, sin puerto publicado, que se borra al terminar). La rama incluye `develop` (`865e85d`: NOTIF-002A e IDENT-001).

| Paso | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_EXIT=0`: no se tocó ningún objeto congelado |
| `deploy_schema.ps1` | `SQL_ERROR_COUNT=0` |
| `test_summary.ps1` | **`FAILED=0`, `CRITICAL_MISSING=0`, `SUMMARY_EXIT=0`**. Ejecutados 385, aprobados 384 y 1 omisión permitida (`XACT_STATE_MINUS_ONE_RUNTIME`). Requeridos: 253 |
| Suite `test_usp_guardar_horarios_grupo` | Pasan los 8 escenarios del PLAN: `GROUP_SCHEDULE_SAVE_SUCCESS`, `_REPLACE`, `_OVERLAP_REJECTED`, `_ADJACENT_ALLOWED`, `_INVALID`, `_SCOPE`, `_TEACHER_CONFLICT_SAVEPOINT` (rollback a savepoint con transacción externa) y `_TEACHER_CONFLICT_OWN_TRANSACTION` (rollback propio sin transacción externa) |
| `test_contract_closure` (`PUBLIC_CANONICAL_RESULTSET`) | Pasa |
| Inventario | 101 SP públicos (repo = instancia) y 65 vistas |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=143` (incluye `HOR_003`/`HOR_004` y los códigos de NOTIF-002A/IDENT-001; el catálogo se regeneró porque `develop` lo traía desactualizado) |
| `scripts/secret-hygiene.ps1` | Exit 0, sin hallazgos |

En la primera corrida fallaron dos detalles de la suite nueva: una expresión dentro de un parámetro de `EXEC` y una palabra prohibida por `AULA_ACTIVE_SQL_REFERENCES_ZERO`. Se corrigieron antes de la corrida final.

## 2. Corrida sobre la BD local de desarrollo (otra sesión, 2026-11-01)

Otra sesión redesplegó `sql_server_asistencias` (local) con `deploy_schema.ps1`:

| Comando | Exit | Resultado |
|---|---:|---|
| `./deploy_schema.ps1` | 0 | Despliegue completo, incluidos `usp_guardar_horarios_grupo`, las vistas `uv_dia` y `uv_horario`, los mensajes `HOR_003` y `HOR_004`, y el permiso de `schema/security/rol_asistencias_runtime_f1_horario_grupo.sql`. |
| `test/test_usp_guardar_horarios_grupo.sql` (sqlcmd, ejecutado solo) | 0 | Las 8 pruebas de la matriz del PLAN pasan. |
| `./scripts/generar-catalogo-mensajes.ps1 -Check` | 0 | `CATALOGO_MENSAJES_OK codigos=143`. |
| `./scripts/secret-hygiene.ps1` | 0 | Sin hallazgos. |

**Por qué la suite completa quedó incompleta en esa BD:** `test_summary.ps1` terminó con `DB GATE INCOMPLETE` (71 ejecutadas, 47 aprobadas, 24 fallidas, exit 1) por `TEST FAILED: PUBLIC_CANONICAL_RESULTSET usp_consultar_asignaturas_paginado canonical_columns=13`.

**Causa (verificada, no es una falla de `develop` ni de F1):**
- `usp_consultar_asignaturas_paginado` se eliminó de `schema/` en #69, junto con otros 17 objetos.
- `deploy_schema.ps1` crea objetos pero no borra los que salen del repo. En `sql_server_asistencias` esos objetos siguen existiendo hasta que se apliquen `migrations/08_eliminar_codigo_sin_uso_up.sql` y `migrations/09_eliminar_validar_grupo_docente_up.sql`. Se verificó con una consulta de solo lectura que esa BD aún tiene `usp_consultar_asignaturas_paginado` y `usp_validar_grupo_exista_para_docente_interno`.
- En una BD nueva (sección 1) esos objetos no existen y `PUBLIC_CANONICAL_RESULTSET` pasa.

**Acción para la BD local:** aplicar las migraciones 08 y 09 antes de volver a correr la suite allí. No se aplicaron desde esta sesión.

## 3. Migración y rollback

- **Orden:** desplegar el esquema (vistas, SP y semilla de mensajes) y después `rol_asistencias_runtime_f1_horario_grupo.sql`.
- **Aditivo:**
  - las vistas solo agregan columnas (`uv_dia.codigo`, `uv_horario.codigoDia`);
  - no se crean ni modifican tablas;
  - `usp_crear_grupo`, `usp_actualizar_grupo` y los objetos congelados no cambian.
- **Rollback:** redesplegar la revisión anterior de BD. El SP nuevo se puede retirar sin afectar datos: `dbo.Horario` conserva las franjas ya guardadas.

## Estado

**VERDE:**
- el gate completo de BD pasa en una BD nueva (sección 1);
- backend: `mvnw -B verify` con 2987 pruebas y 0 fallos, sobre `develop` `e6e54e7c`;
- frontend: 1356 de 1356 pruebas y `ng build` OK.
