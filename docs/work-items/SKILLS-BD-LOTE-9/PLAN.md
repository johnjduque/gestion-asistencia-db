---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 9: periodos, festivos y recesos

## Contexto

Lote 9 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 23 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 8. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió `test/test_skills_lote9_caracterizacion.sql`
(4 internos de periodo no tenían prueba directa) y se corrió sobre el código previo (pasaron los 4). Después del refactor pasan
los 4 y las pruebas de dominio: festivos CULM-001 B.1, sesión cancelada, cierre masivo (C, FIX-CIERRE-001/002, PRU-15), recesos,
gestión de periodos, revisión final P3, calendario ATA P2, cierre de contrato, D.9, DEC-073 y calendario SES-GEN-01.

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Validadores de periodo | `usp_resolver_institucion_gestor_periodo_interno`, `usp_validar_fechas_periodo_academico_interno`, `usp_validar_solape_periodo_academico_interno`, `usp_validar_periodo_abierto_sesion_interno`, `usp_validar_ejecutor_administrador_periodo_interno`, `usp_validar_receso_academico_interno` | `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` donde faltaba (con transacción abierta relanza; sin ella, `SYS_001`) |
| Núcleos de festivos y recesos | `usp_aplicar_festivos_grupo_interno`, `usp_cancelar_sesiones_receso_interno`, `usp_cargar_dias_festivos_interno` | `PASO n`, lecturas laterales por vistas e `IIF` en lugar de `ISNULL` sobre variables. El bloqueo de `dbo.Sesion` y las escrituras siguen en las tablas |
| CRUD de periodos y recesos | `usp_crear_periodo_academico`, `usp_actualizar_periodo_academico`, `usp_eliminar_periodo_academico`, `usp_crear_receso_academico`, `usp_retirar_receso_academico` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, `IIF` en lugar de `COALESCE` y las lecturas sin bloqueo por vistas; los `UPDLOCK, HOLDLOCK` y los `DELETE` siguen en las tablas |
| Fachadas de festivos | `usp_aplicar_festivos_grupo`, `usp_aplicar_festivos_periodo`, `usp_cargar_dias_festivos` | `PASO n`, `IF` con `BEGIN/END`, grupo por `uv_grupo_registro` e `IIF` en lugar de `ISNULL` |
| Cierre masivo | `usp_ejecutar_cierre_masivo_periodo` | `PASO` numerados, `IF` con `BEGIN/END` (también los `COMMIT` de una línea) y lecturas sin bloqueo por vistas. El orden de bloqueos de §2.0 no cambia: `PeriodoAcademico`, `RevisionCancelacion` y `EstudianteGrupo` con `UPDLOCK, HOLDLOCK` y los `UPDATE` siguen en las tablas |
| Consultas | `usp_consultar_carga_festivos_anio`, `usp_consultar_dias_festivos`, `usp_consultar_sesiones_festivo_con_asistencia_paginado`, `usp_consultar_destinatarios_receso_academico`, `usp_consultar_recesos_periodo` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Vistas nuevas | `uv_periodo_academico_fechas`, `uv_receso_academico_registro`, `uv_sesion_cancelacion`, `uv_asistencia_registro`, `uv_toma_asistencia_registro`, `uv_grupo_registro`, `uv_estudiante_grupo_registro`, `uv_revision_cancelacion_registro` | Delgadas, una tabla cada una, sin filtros ni cálculos. Inventario de `transaccion-procedimiento.md`: 120 vistas |
| Pruebas | `test/test_skills_lote9_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 4 IDs nuevos `SKL9_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 9 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | |

Por qué vistas nuevas: la skill prohíbe cambiar la forma de una vista existente, y las que había no servían tal cual.
`uv_periodo_academico` no expone `fechaCierreUtc`; `uv_periodo_receso_academico` filtra los recesos activos (el borrado de un
periodo y el retiro de un receso también ven los retirados); `uv_grupo`, `uv_estudiante_grupo` y `uv_revision_cancelacion` unen
estadísticas, identidad y catálogos, demasiado para una búsqueda por llave dentro de una transacción con bloqueos. Las vistas
`*_registro` devuelven las mismas filas que su tabla.

Sin migración: el lote solo cambia cuerpos de SP y agrega vistas; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo
del Golden Path ni de los manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- `usp_validar_periodo_abierto_sesion_interno` gana `TRY/CATCH`; sigue sin inicializar sus salidas cuando el periodo está abierto
  o la sesión no existe (el llamador cuenta con eso, como antes).
- Costo estimado de la búsqueda del periodo de una sesión en `usp_validar_periodo_abierto_sesion_interno`: 0,0099 antes y 0,0197
  ahora (`uv_sesion` une `uv_grupo`). Es una búsqueda por llave primaria de una fila; no se nota en tiempo.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (las vistas nuevas quedan sin uso y se pueden borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
