---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-10
---

# PLAN — HU018-HU019: plan de estudios por semestres y horas programadas del estudiante

## Identidad y objetivo

- **HU018, estructura curricular por semestres:** el estudiante consulta los planes de estudio activos de sus programas, con sus semestres, sus asignaturas, los créditos, el carácter y cuáles cursa hoy.
- **HU019, horas de cada materia:** el estudiante compara las horas a las que asistió con las dictadas y con las programadas del grupo. Las dos primeras ya salían de `usp_consultar_resumen_asistencia_estudiante` (CULM-001 B.2); aquí se agrega el total programado.
- **Decisión de John (2026-11-10):** la barra de HU019 es por horas, porque la aplicación no maneja notas ni asignaturas aprobadas.
- **Privacidad:** un estudiante solo ve información propia. Los dos SP resuelven al estudiante desde el ejecutor y no reciben identificadores de otro estudiante.
- **Contrato HTTP, análisis de impacto y validación de las 3 capas:** están en el work item homónimo del backend.

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_plan_estudio_estudiante` | Nuevo (READ_QUERY_RESULTSET, 18 columnas, sin paginación) |
| `usp_consultar_horas_programadas_estudiante` | Nuevo (READ_QUERY_RESULTSET, 4 columnas, sin paginación) |
| `schema/security/rol_asistencias_runtime_hu018_hu019.sql` | `GRANT EXECUTE` aditivo de los dos SP |
| `migrations/30_hu018_hu019_plan_horas_estudiante_up.sql` y `_down.sql` | Los dos SP y sus permisos; el `down` solo los elimina |
| `test/test_hu018_hu019_plan_horas_estudiante.sql` | Nuevo (7 casos) |
| `test/test_hu018_hu019_migraciones.sql` y `test/test_hu018_hu019.ps1` | Nuevo: migración 30 up → down → up dentro de una transacción revertida |
| `test_suite.sql`, `test_summary.ps1`, `test/test_contract_closure.sql`, `test/test_public_objects.sql` | Registro de las pruebas, exclusión READ_QUERY_RESULTSET de los dos SP y verificación de permisos |

Ningún objeto existente cambia. En particular no se tocan `usp_consultar_resumen_asistencia_estudiante` ni `usp_consultar_materias_estudiante`: el backend une las horas programadas por `idGrupo`.

## Reglas de los SP

### `usp_consultar_plan_estudio_estudiante(@idUsuarioEjecutor, @idCorrelacion)`

- Planes ACTIVOS (`uv_plan_estudio.estaActivoPlanEstudio = 1`: el plan y su programa están activos) de los programas del estudiante (`EstudiantePrograma`).
- Una fila por semestre del plan y asignatura con vínculo activo (`AsignaturaPlanEstudio.estaActivo = 1`) y asignatura activa.
- Un semestre sin asignaturas devuelve una fila con las columnas de la asignatura en `NULL`, para que la estructura se vea completa.
- `cursando = 1` si el estudiante tiene una matrícula con el código del parámetro `MATRICULA/ESTADO_INSCRITA` en un grupo de la asignatura. Es la misma regla de `usp_consultar_materias_estudiante`. `idGrupoCursando` y `nombreGrupoCursando` identifican ese grupo; si hay varios, el de menor código.
- Orden: `nombrePrograma`, `inp`, `numeroSemestre`, orden del carácter y nombre de la asignatura.
- Columnas: `idPrograma, nombrePrograma, idPlanEstudio, inpPlanEstudio, idSemestrePlanEstudio, numeroSemestre, idAsignaturaPlanEstudio, idAsignatura, codigoAsignatura, nombreAsignatura, creditos, codigoComponente, nombreComponente, codigoCaracter, nombreCaracter, cursando, idGrupoCursando, nombreGrupoCursando`.

### `usp_consultar_horas_programadas_estudiante(@idUsuarioEjecutor, @idCorrelacion)`

- Una fila por matrícula inscrita del estudiante: el mismo universo de "Mis materias".
- `sesionesProgramadas` y `horasProgramadas` cuentan todas las sesiones del grupo que no están canceladas, ya dictadas o por dictar. Salen de `uv_cumplimiento_sesion_grupo`, que excluye `dbo.SesionCancelacion`, y de `ufn_horas_sesion`.
- Las horas dictadas del resumen por horas son un subconjunto de las programadas (sesiones vencidas con registro), así que nunca las superan.
- Un grupo sin sesiones devuelve 0 y 0.
- Columnas: `idEstudianteGrupo, idGrupo, sesionesProgramadas, horasProgramadas`.

### Comunes

- `VAL_001` (THROW 51000) si el ejecutor es nulo. Quien no es estudiante obtiene 0 filas.
- Solo lectura. No llevan `SET XACT_ABORT ON`: un rechazo de validación no debe dejar sin poder confirmar la transacción de quien los llama.

## Reglas aplicadas (AGENTS.md)

- Sin cambios de tablas ni de objetos congelados.
- Se leen objetos existentes: `uv_semestre_plan_estudio`, `uv_plan_estudio`, `uv_asignatura_plan_estudio`, `uv_estudiante_grupo`, `uv_grupo`, `uv_cumplimiento_sesion_grupo`, `Estudiante`, `EstudiantePrograma` y `CatalogoParametro`.
- No se agregan mensajes nuevos; se usa `VAL_001`.
- El rol runtime recibe solo `EXECUTE` sobre los dos SP públicos.

## Despliegue y rollback

- Orden (DEC-060): primero la migración 30 y después el backend.
- Rollback: `30_hu018_hu019_plan_horas_estudiante_down.sql`. Solo elimina los dos SP; no hay datos que deshacer.
