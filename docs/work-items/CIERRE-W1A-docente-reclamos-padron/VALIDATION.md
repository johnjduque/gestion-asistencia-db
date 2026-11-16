# CIERRE-W1A (BD): reclamos y padron del docente en servidor

Fecha: 2026-11-16. Rama `feat/cierre-w1a-docente-reclamos` desde `repo-antiguo/develop` (d49c034). Contrato y plan: backend
(`alejovh12/AsistenciasUCO`), `docs/work-items/CIERRE-W1A-docente-reclamos-padron/` (CONTRACT.md y PLAN.md). Orden de mezcla: BD, backend, frontend.

## Cambios

| Archivo | Cambio |
| :--- | :--- |
| `schema/stored-procedures/usp_consultar_solicitudes_revision_docente.sql` | Parametros opcionales AL FINAL: `@busqueda NVARCHAR(100) = NULL` (subcadena en nombre del estudiante, nombre y codigo de la asignatura y justificacion) y `@idGrupo UNIQUEIDENTIFIER = NULL`. Resultset sin cambios (31 columnas). La titularidad (`doc.usuario`) se mantiene: un grupo ajeno da 0 filas |
| `schema/stored-procedures/usp_consultar_estudiantes_grupo_ambito_paginado.sql` | `@busqueda NVARCHAR(100) = NULL` al final (nombre completo o documento, antes de paginar). Resultset sin cambios (8 columnas) y ambito validado antes de leer filas |
| `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`, `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256` | Hash nuevo del SP de reclamos del docente (`freeze-manifest.ps1 -Mode UpdateCulm001D` y `lb004d-manifest.ps1 -Mode Generate`) |
| `test/test_cierre_w1a_docente_reclamos_padron.sql`, `test_suite.sql`, `test_summary.ps1` | 10 marcadores `W1A_*` (busqueda, campos, filtro de grupo, paginacion y total, compatibilidad sin parametros, padron, ambito `SEC_002`, `@@TRANCOUNT`) |
| `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, `especificacion_sp_endpoints.md` | Parametros y mapeo de endpoints |

Sin migracion: solo `CREATE OR ALTER` con parametros opcionales al final (un backend viejo, que no los envia, sigue funcionando). Sin cambios
de permisos: `EXECUTE` ya estaba concedido a `rol_asistencias_runtime` sobre ambos SP (`rol_asistencias_runtime_lb004d.sql`, `_culm001_a.sql`).

## Evidencia (SQL Server 2022 desechable `sql_gate_w1a`, despliegue desde cero)

| Paso | Resultado |
| :--- | :--- |
| `deploy_schema.ps1` sobre BD inexistente | exit 0 |
| `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` + `cleanup_lb004d_fixture.ps1` | `TOTAL_EXPECTED=695 TOTAL_EXECUTED=874 PASSED=873 FAILED=0 SKIPPED=1` (el skip es `XACT_STATE_MINUS_ONE_RUNTIME`, permitido por el gate: `ALLOWED_SKIPPED=1`), exit 0 |
| Marcadores nuevos | `W1A_REC_01..05`, `W1A_PAD_01..04`, `W1A_TRANCOUNT_ZERO`: todos `TEST_PASS` |
| `freeze-manifest.ps1 -Mode Verify` / `lb004d-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK ... culm001_d=81` / `LB004D_MANIFEST_OK entries=9` |

Nota: la prueba nueva se escribio junto al cambio y no se capturo una corrida en rojo previa contra los SP anteriores.
El contenedor se elimino al terminar; no se toco `sql_server_asistencias`.
