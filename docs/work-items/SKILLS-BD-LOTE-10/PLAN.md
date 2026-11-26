---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 10: indicadores y consultas

## Contexto

Lote 10 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 23 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 9. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos valores en
los resultsets, mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió
`test/test_skills_lote10_caracterizacion.sql` (los 3 resolutores del periodo de los KPI no tenían prueba directa) y se corrió sobre
el código previo (pasaron los 3). Después del refactor pasan los 3 y las pruebas de dominio de los 20 SP públicos (KPI de coordinador,
decano e institución, aforo, alerta temprana, alertas y revisiones CULM-001 C, horas B.2, matriz y resúmenes W2A/W2B/W3I/W3M,
puntos de control, ATA P1, consultas transversales, cierre de contrato y correlación VAL-OBS-03).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Resolutores del periodo de los KPI | `usp_resolver_periodo_kpi_interno`, `usp_resolver_periodo_kpi_facultad_interno`, `usp_resolver_periodo_kpi_institucion_interno` | `DECLARE` en la cabecera, `PASO n` y `TRY/CATCH` que relanza el mismo error |
| KPI | `usp_consultar_kpis_coordinador`, `usp_consultar_kpis_decano`, `usp_consultar_kpis_institucion` | `DECLARE` en la cabecera (los que dependen del ámbito resuelto quedan como `SET` en su paso) y `TRY/CATCH` de lectura. Las consultas y sus pistas (`OPTION (RECOMPILE)`, `NO_PERFORMANCE_SPOOL`) no cambian |
| Consultas del coordinador y del decano | `usp_consultar_aforo_grupos_facultad`, `usp_consultar_alerta_temprana_programa`, `usp_consultar_resumen_asistencia_estudiante_programa`, `usp_consultar_resumen_docentes_programa`, `usp_consultar_historial_grupos_docente_programa` | `DECLARE` en la cabecera, `IF` con `BEGIN/END`, sin `ISNULL` sobre columnas o parámetros y `TRY/CATCH` de lectura |
| Consultas del estudiante | `usp_consultar_alertas_estudiante`, `usp_consultar_resumen_asistencia_estudiante`, `usp_consultar_resumen_materias_estudiante` | Igual, más `PASO n` y estudiante/matrícula por vistas |
| Consultas del docente | `usp_consultar_matriz_asistencia_grupo_docente_paginado`, `usp_consultar_resumen_asistencia_grupo_docente_paginado`, `usp_consultar_resumen_tomas_sesion`, `usp_consultar_resumen_grupos_docente` | Igual, con `IIF` en lugar de `ISNULL` sobre columnas de `LEFT JOIN` y sesión/transiciones/revisión por vistas |
| Consultas de ámbito | `usp_consultar_asignaturas_ambito_consolidado`, `usp_consultar_docentes_ambito_consolidado`, `usp_consultar_historial_estudiante` | Ya relanzaban en el `CATCH`: solo `PASO n` en el restablecimiento del contexto y en el `CATCH` |
| Motor de alertas | `usp_consultar_grupos_pendientes_evaluacion_alertas`, `usp_evaluar_alertas_inasistencia_grupo` | `PASO n`, `IF` con `BEGIN/END`, sin `ISNULL` y lecturas sin bloqueo por vistas. En la evaluación, los `UPDLOCK, HOLDLOCK` (`EvaluacionAlertaGrupo`, `AlertaInasistencia`, `RevisionCancelacion`), el `NOT EXISTS` sobre la tabla destino del `INSERT` y todas las escrituras siguen en las tablas |
| Vista nueva | `uv_evaluacion_alerta_grupo` | Delgada, una tabla, sin cálculos. Inventario de `transaccion-procedimiento.md`: 121 vistas |
| Pruebas | `test/test_skills_lote10_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 3 IDs nuevos `SKL10_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 10 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | |

Sin migración: el lote solo cambia cuerpos de SP y agrega una vista; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo
del Golden Path ni de los manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- Metadatos del resultset: en `usp_consultar_resumen_asistencia_grupo_docente_paginado` (`tieneAdvertenciaVigente`,
  `tienePerdidaVigente`, `requiereAccionDocente`) y en `usp_consultar_resumen_tomas_sesion` (`minutosAsistidos`, `minutosFalta`,
  `minutosExcusa`, `minutosSinRegistro`, `codigoEstadoSesionEstudiante`, `tomasAusentes`) SQL Server describe ahora la columna como
  anulable, porque un `IIF` no garantiza `NOT NULL` como `ISNULL`. Los valores no cambian (nunca son `NULL`) y el tipo es el mismo.
  Se comparó `sys.dm_exec_describe_first_result_set_for_object` antes y después en los 20 SP con resultset: es la única diferencia.
- Rendimiento: se compararon los KPI de institución, decano y coordinador y la consulta de grupos pendientes con copias del código
  previo sobre la misma base: mismo resultado (salida idéntica) y tiempos equivalentes (dentro de la variación entre corridas).

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (la vista nueva queda sin uso y se puede borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
