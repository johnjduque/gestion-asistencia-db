---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 13: sesiones y horarios

## Contexto

Lote 13 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 28 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 12. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió `test/test_skills_lote13_caracterizacion.sql`
para los cinco internos sin prueba directa (`usp_validar_sesion_exista_por_id_interno`, `usp_validar_docente_titular_sesion_interno`,
`usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`, `usp_validar_horarios_grupo_interno` y
`usp_guardar_horarios_grupo_interno`) y se corrió sobre el código previo (pasó). Después del refactor pasa y las 22 pruebas de dominio
de los 28 SP dan exactamente el mismo resultado que antes (MRM, ATA P2, SES-01, SES-GEN-01, DEC-073, DEC-076/077, CULM-001 A, B.1, B.2
y D.9, recesos, PRU-15, precarga, sesiones manuales, consultas paginadas, consultas de coordinador y decano, P3 y cierre de contrato).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Destinatarios y catálogos | `usp_consultar_destinatarios_sesion_cancelada`, `_sesion_manual`, `_solicitud_sesion`, `usp_consultar_motivos_cancelacion_sesion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Calendario y horario | `usp_consultar_horario_estudiante`, `usp_consultar_sesiones_calendario_docente`, `_estudiante` | Igual |
| Bandejas paginadas | `usp_consultar_solicitudes_sesion_coordinador_paginado`, `_docente_paginado`, `usp_consultar_sesiones_facultad_paginado`, `usp_consultar_sesiones_grupo_paginado`, `usp_consultar_asistencias_sesion_paginado` | Igual; en la del docente `IIF` en lugar de `ISNULL`; las tres últimas restauran el contexto en el `CATCH` como antes |
| Solicitudes y cancelación | `usp_aprobar_solicitud_sesion`, `usp_rechazar_solicitud_sesion`, `usp_cancelar_sesion`, `usp_cancelar_sesion_coordinador` | `IF` con `BEGIN/END`, `PASO` en el `CATCH` y lecturas sin bloqueo por vistas; el `UPDLOCK, HOLDLOCK` de la sesión y las escrituras siguen en las tablas |
| Generación | `usp_generar_sesiones_grupo_v2`, `usp_precargar_sesiones_grupo_interno` | `PASO n`, `IF` con `BEGIN/END`; la precarga lee por vistas, usa `IIF` en lugar de `COALESCE` y conserva en las tablas el correlativo con bloqueo y las escrituras |
| Validadores internos | `usp_validar_coordinador_sesion_interno`, `_docente_titular_`, `_estudiante_pertenece_`, `_horarios_grupo_`, `_rango_calendario_`, `_sesion_exista_por_id_`, `_sesion_mismo_dia_`, `_sesion_ventana_registro_`, `_solape_sesion_`, `usp_guardar_horarios_grupo_interno` | Inicialización de las salidas en el cuerpo (`PASO 0`), `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas; los que no tenían `TRY` ahora tienen uno que relanza el error (mismo flujo) |
| Vistas nuevas | `uv_programa_registro`, `uv_facultad_registro`, `uv_solicitud_sesion_registro`, `uv_horario_registro`, `uv_sesion_procedencia_clasificacion_registro` | Delgadas, una tabla cada una, sin filtros ni cálculos. Inventario de `transaccion-procedimiento.md`: 131 vistas |
| Pruebas | `test/test_skills_lote13_caracterizacion.sql` (nuevo, en `test_suite.sql`) | IDs nuevos `SKL13_R01` a `SKL13_R04` en `test_summary.ps1` |
| Documentación | Addendum del lote 13 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | |

Por qué vistas nuevas: la skill prohíbe cambiar la forma de una vista existente; `uv_programa`, `uv_facultad`, `uv_solicitud_sesion` y
`uv_horario` unen otras vistas (y algunas filtran), y `SesionProcedenciaClasificacion` no tenía vista.

Sin migración: el lote solo cambia cuerpos de SP y agrega vistas; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo del
Golden Path ni de los manifiestos congelados cambia (`usp_generar_sesiones_grupo`, el SP congelado que llama `usp_generar_sesiones_grupo_v2`, no se toca).

## Diferencias observables (ninguna de negocio)

Ninguna: se comparó `sys.dm_exec_describe_first_result_set_for_object` antes y después en los 28 SP y los metadatos son idénticos.
En los tres validadores que no tenían `TRY` (`_docente_titular_`, `_sesion_mismo_dia_`, `_rango_calendario_`) el `CATCH` nuevo solo
relanza, así que un error del motor llega al llamador igual que antes.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (las vistas nuevas quedan sin uso y se pueden borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
