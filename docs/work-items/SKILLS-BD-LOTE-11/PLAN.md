---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 11: revisiones de cancelación y reclamos

## Contexto

Lote 11 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 15 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 10. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos valores en
los resultsets, mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió
`test/test_skills_lote11_caracterizacion.sql` (`usp_consultar_destinatarios_reclamo_asistencia` no tenía prueba directa) y se corrió
sobre el código previo (pasó). Después del refactor pasa y pasan las pruebas de dominio de los 15 SP: CULM-001 C (revisiones,
cierre masivo, audiencias), D.1 (plazo), D.2 (soportes y categoría), reclamos del estudiante y del docente, SES-01, SES-04, DEC-073,
puntos de control (tomas y bandeja de reclamos), PRU-13, PRU-15, REC3, LB-004D, comandos de asistencia y cierre de contrato.

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Destinatarios | `usp_consultar_destinatarios_reclamo_asistencia`, `usp_consultar_destinatarios_revision_cancelacion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Consultas de reclamos | `usp_consultar_detalle_solicitud_revision_docente`, `usp_consultar_solicitudes_revision_estudiante`, `usp_consultar_asistencias_grupo_ambito_paginado` | Igual; `soportesJson` por `OUTER APPLY` + `IIF` (antes, `ISNULL`) |
| Bandejas de revisiones | `usp_consultar_revisiones_cancelacion_coordinador_paginado`, `_decano_paginado`, `_docente_paginado` | Igual; el `ISNULL` sobre `STRING_AGG` queda (agregación, permitido) |
| Revisiones de cancelación | `usp_actualizar_resolutores_revisiones_cancelacion`, `usp_decidir_revision_cancelacion`, `usp_resolver_revision_cancelacion` | `PASO n`, `IF` con `BEGIN/END`, `IIF` en lugar de `ISNULL` y lecturas sin bloqueo por vistas. Los `UPDLOCK, HOLDLOCK` y las escrituras siguen en las tablas |
| Reclamos | `usp_radicar_solicitud_revision_asistencia`, `usp_resolver_solicitud_revision_asistencia`, `usp_retirar_solicitud_revision_asistencia` | `IF` con `BEGIN/END`, `IIF` en lugar de `ISNULL`, `PASO` en el `CATCH` y lecturas sin bloqueo por vistas. Los bloqueos y las escrituras siguen en las tablas |
| Interno | `usp_sincronizar_asistencia_estudiante_interno` | La inicialización de las salidas pasa de la cabecera al cuerpo (`PASO 0`), `IF` con `BEGIN/END` y lecturas sin bloqueo por vistas |
| Vistas nuevas | `uv_solicitud_revision_asistencia_registro`, `uv_sesion_registro`, `uv_detalle_asistencia_registro`, `uv_archivo_soporte_registro` | Delgadas, una tabla cada una, sin filtros ni cálculos. Inventario de `transaccion-procedimiento.md`: 125 vistas |
| Vista ampliada | `uv_revision_cancelacion_registro` | Creada en el lote 9 (aún no está en `develop`): agrega al final el resto de columnas de la tabla; las previas no cambian |
| Pruebas | `test/test_skills_lote11_caracterizacion.sql` (nuevo, en `test_suite.sql`) | ID nuevo `SKL11_R01_DESTINATARIOS_RECLAMO` en `test_summary.ps1` |
| Documentación | Addendum del lote 11 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | |

Por qué vistas nuevas: la skill prohíbe cambiar la forma de una vista existente y no había vista de una tabla para
`SolicitudRevisionAsistencia`, `DetalleAsistencia` ni `ArchivoSoporte`; `uv_sesion` une `uv_grupo`. `uv_revision_cancelacion_registro`
se amplía en lugar de crear otra vista de la misma tabla porque todavía no se ha publicado.

Sin migración: el lote solo cambia cuerpos de SP y vistas; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo del Golden
Path ni de los manifiestos congelados cambia (`usp_radicar_solicitud_revision_asistencia_v3`, el del manifiesto CULM-001 D, no se toca).

## Diferencias observables (ninguna de negocio)

- Metadatos del resultset: en `usp_consultar_detalle_solicitud_revision_docente` y `usp_consultar_solicitudes_revision_estudiante`
  SQL Server describe ahora `soportesJson` como anulable, porque un `IIF` no garantiza `NOT NULL` como `ISNULL`. El valor no cambia
  (`'[]'` sin soportes) y el tipo es el mismo. Se comparó `sys.dm_exec_describe_first_result_set_for_object` antes y después en los
  15 SP: es la única diferencia.
- `usp_sincronizar_asistencia_estudiante_interno` inicializa sus salidas después de `SET NOCOUNT ON` (antes, entre `AS` y `BEGIN`):
  mismos valores y mismo orden respecto de la primera validación.
- `usp_actualizar_resolutores_revisiones_cancelacion`: el `ISNULL` sobre `CONCAT(...)` de las novedades no tenía efecto (`CONCAT`
  nunca devuelve `NULL`) y se quitó; el `IF` siguiente ya dejaba `'[]'` sin novedades.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (las vistas nuevas quedan sin uso y se pueden borrar;
las columnas agregadas a `uv_revision_cancelacion_registro` no las usa nadie más).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
