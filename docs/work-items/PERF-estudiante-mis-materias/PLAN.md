---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# PLAN — PERF-EST-MM: rendimiento de "Mis materias" del estudiante

## Identidad y objetivo

- **Problema:** abrir el detalle de una materia del estudiante (`GET /api/v1/estudiante/materias/{id}/sesiones`) y la vista de tomas que lo complementa se vuelven lentas con datos reales. Diagnóstico del 2026-11-19 (solo lectura):
  1. `ufn_calcular_fecha_limite_justificacion` es una función escalar de varias sentencias (lee dos parámetros, consulta `sys.time_zone_info` y usa `AT TIME ZONE`). SQL Server no la expande en línea; usada **por fila** en `uv_sesion_estudiante_reclamo` y `uv_asistencia_toma_estudiante` obliga a planes en serie evaluados fila por fila.
  2. `uv_asistencia_toma_estudiante` llama además `ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO')` dentro del `OUTER APPLY`, una vez por fila de toma.
  3. `usp_consultar_sesiones_materia_estudiante` calculaba la fecha límite de **todas** las sesiones de la materia antes de paginar.
  4. Faltaban índices en columnas de filtro y unión: `EstudianteGrupo(estudiante)`, `EstudianteGrupo(grupo)`, `Grupo(asignatura)` y `Asistencia(sesion)` (el único índice de `Asistencia` empieza por `estudianteGrupo`).
- **Objetivo:** el mismo resultado con menos trabajo. Sin cambios de contrato: mismas columnas, tipos, orden, total y valores.

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `ufn_calcular_fecha_limite_justificacion_conjunto` | Nueva función de tabla en línea: la misma regla de la escalar (CULM-001 D.1, HU026B). Los parámetros y la zona se leen como un conjunto constante; solo la aritmética de fechas es por fila |
| `ufn_calcular_fecha_limite_justificacion` | **Sin cambio** (la siguen usando los llamadores de un solo valor: `usp_internal_validar_plazo_justificacion`, `uv_falta_reclamable_estudiante`, `usp_consultar_faltas_sesion_aviso`) |
| `uv_sesion_estudiante_reclamo` | `CROSS APPLY` a la función en línea en lugar de la escalar. Mismas columnas |
| `uv_asistencia_toma_estudiante` | `esReclamable` con la función en línea; el código `RECLAMO/ESTADO_RETIRADO` se lee una vez (misma lectura que `ufn_obtener_parametro`). Mismas columnas |
| `usp_consultar_sesiones_materia_estudiante` | Filtra, cuenta y pagina con las columnas baratas y calcula el límite solo para las filas de la página. Mismo resultset (`READ_QUERY_RESULTSET`) |
| `schema/tables/EstudianteGrupo.sql`, `Grupo.sql`, `Asistencia.sql` | Índices `IX_EstudianteGrupo_Estudiante` (INCLUDE grupo, estado), `IX_EstudianteGrupo_Grupo` (INCLUDE estudiante, estado), `IX_Grupo_Asignatura` (INCLUDE periodoAcademico, docente), `IX_Asistencia_Sesion` (INCLUDE estudianteGrupo). Sin columnas nuevas |
| `migrations/59_perf_estudiante_mis_materias_up.sql` y `_down.sql` | Up: función, dos vistas, SP e índices. Down: textos de develop de las dos vistas y del SP, elimina la función y los índices |
| `scripts/migrar-marcadores.json` | Marcadores de la 59 (y su hash en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`, junto con la vista y el SP) |
| `test/test_perf_estudiante_mis_materias.sql` | Nueva, registrada en `test_suite.sql` |

## Decisiones

- **La escalar se conserva.** Reescribirla para que llame a la función de tabla no es posible de forma segura: `deploy_schema.ps1` despliega las funciones por nombre y la escalar va antes. Se deja intacta y la prueba `PERF_MM_01`/`PERF_MM_02` garantiza que las dos den lo mismo.
- **Zona inválida.** `AT TIME ZONE` falla con un nombre inexistente; la función de tabla lo reemplaza por `'UTC'` antes de usarlo y descarta ese resultado (`zonaValida = 0` devuelve NULL), igual que la escalar.
- **Permisos.** Sin cambios: el runtime lee las vistas y ejecuta el SP; la función se alcanza por encadenamiento de propiedad (`dbo`).
- **`uv_falta_reclamable_estudiante`** también usa la escalar por fila; queda fuera de este cambio (pantalla de alertas) y es candidata a la misma corrección.

## Validación

Ver [VALIDATION.md](VALIDATION.md).
