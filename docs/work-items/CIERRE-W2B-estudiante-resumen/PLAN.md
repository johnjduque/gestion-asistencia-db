---
status: active
type: work-item
scope: database
last-reviewed: 2026-11-16
---

# CIERRE-W2B (BD): sesiones y resumen del estudiante resueltos en la base

Contrato completo en `docs/work-items/CIERRE-W2B-estudiante-resumen/CONTRACT.md` del repositorio de backend.

| Objeto | Cambio |
|---|---|
| `uv_materia_estudiante` (nueva) | Una fila por matricula del estudiante con asignatura, grupo, creditos y estado. Fuente unica de las materias del estudiante. |
| `usp_consultar_materias_estudiante` | Lee `uv_materia_estudiante` (mismo resultset de 5 columnas y mismo orden). |
| `usp_consultar_resumen_materias_estudiante` (nuevo) | Una fila: `totalMaterias`, `materiasEnRiesgo` (NULL si no hay umbrales), `totalHorasFalta`, `totalCreditos`, sobre las mismas materias que el listado. |
| `usp_consultar_sesiones_materia_estudiante` | Orden `fechaHoraInicio, numero, id` (antes `numero, fechaHoraInicio, id`) y `@idGrupo UNIQUEIDENTIFIER = NULL` al final (filtro opcional). Mismo resultset de 13 columnas. |

Permisos: `schema/security/rol_asistencias_runtime_w2b_estudiante_resumen.sql` (SP nuevo). Los demas objetos no cambian de firma publica
(solo un parametro opcional con valor por defecto). Pruebas: `test/test_w2b_estudiante_resumen.sql` (`W2B_*`), registrada en
`test_suite.sql` y `test_summary.ps1`; el SP nuevo se agrego a las excepciones de `READ_QUERY_RESULTSET` de `test/test_contract_closure.sql`.
Sin migracion: son objetos `CREATE OR ALTER` sin datos nuevos.
