---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 14: objetos congelados

## Contexto

Lote 14 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 38 SP con hash en los manifiestos de
`docs/contracts/` o en `test_golden_path_immutability.sql`. Va en la rama larga `refactor/skills-bd`, sobre el lote 13. Decisión D5 del
responsable del proyecto: corregir también el estilo de los congelados, sin cambiar su comportamiento, y regenerar sus manifiestos.
Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets, mismos códigos de rechazo y mismo flujo de
error).

Antes de tocar código se escribió `test/test_skills_lote14_caracterizacion.sql` para los dos SP sin prueba directa
(`usp_validar_valor_parametro_externo_interno` y `usp_actualizar_sesion_interno`) y se corrió sobre el código previo (pasó). Se tomó
una línea base de 59 archivos de prueba de dominio que cubren los 38 SP (Golden Path, UTC-D06, SES-01, SES-GEN-01, MRM, CULM-001 A, B.1,
B.2, D.1 a D.9, LB-004D, INT-004, PC, P3, DEC-078, PRU-13/15, REC3, comparativas y tendencia, coordinador y decano, matrícula por
token). Después del refactor dan el mismo resultado (dos archivos que fallaban en la base de desarrollo por datos sobrantes de corridas
previas ahora pasan; en el CI parten de una base limpia).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Fachadas de sesión | `usp_crear_sesion`, `_v2`, `usp_actualizar_sesion`, `_v2` | `PASO 1` en `TRY`, `CATCH` que solo relanza, `PASO 3` de retorno |
| Núcleos de sesión | `usp_crear_sesion_interno`, `usp_actualizar_sesion_interno`, `usp_clasificar_procedencia_sesion`, `usp_generar_sesiones_grupo`, `usp_registrar_asistencias_sesion` | `DECLARE` a la cabecera, `PASO n`, `IF` con `BEGIN/END`, `IIF` en lugar de `COALESCE`, lecturas sin bloqueo por vistas; `UPDLOCK, HOLDLOCK` y escrituras en las tablas |
| Consultas y reportes | comparativas, tendencia, configuración de reclamos, periodos, programas, grupo de facultad, sesiones de materia, soporte autorizado, reclamos del docente, auditoría, parámetros, consolidado, cambios de parámetro, acceso a reporte | `DECLARE` en la cabecera, `PASO n`, `IIF`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Parámetros | `usp_actualizar_parametro`, `usp_sincronizar_parametro_catalogo_externo`, `usp_validar_valor_parametro_externo_interno` | `PASO n`, `IF` con `BEGIN/END`, `IS NULL` en lugar de `ISNULL`, lecturas por vistas; el validador gana un `TRY` que relanza |
| Usuarios | `usp_admitir_estudiante`, `usp_crear_coordinador`, `usp_crear_decano` | `DECLARE` a la cabecera, `PASO` en el `CATCH`, `IF` con `BEGIN/END`, lecturas por vistas |
| Reclamos y soportes | `usp_registrar_archivo_soporte`, `usp_radicar_solicitud_revision_asistencia_v2`, `_v3`, `usp_radicar_solicitud_revision_interno`, `usp_validar_plazo_justificacion_interno` | Igual; el plazo gana un `TRY` que relanza |
| Matrícula por token | `usp_validar_token_matricula_publico`, `usp_matricular_por_token_interno` | Igual; el token se sigue resolviendo por hash o PIN en el núcleo (E7) |
| Marca `SP_SISTEMA` | `usp_sincronizar_parametro_catalogo_externo`, `usp_validar_token_matricula_publico` | Comentario de cabecera (E1) |
| Vistas nuevas | `uv_administrador_registro`, `uv_asignatura_registro`, `uv_parametro_registro`, `uv_parametro_edicion_registro`, `uv_sincronizacion_parametro_externo_registro`, `uv_estudiante_programa_registro`, `uv_token_matricula_grupo_registro` | Delgadas, una tabla cada una, sin filtros ni cálculos. Inventario de `transaccion-procedimiento.md`: 138 vistas |
| Manifiestos | `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`, `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`, `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256` | Regenerados con `freeze-manifest.ps1 -Mode GeneratePostFreeze`, `-Mode UpdateCulm001D` y `lb004d-manifest.ps1 -Mode Generate`. `DB_DEVELOP_FREEZE_MANIFEST.sha256` (DB-GP-001C) no cambia: las líneas `SUPERSEDES` siguen nombrando su hash original |
| Pruebas | `test/test_skills_lote14_caracterizacion.sql` (nuevo, en `test_suite.sql`) | IDs nuevos `SKL14_R01_VALOR_PARAMETRO_EXTERNO` y `SKL14_R02_ACTUALIZAR_SESION` en `test_summary.ps1` |
| Documentación | Addendum del lote 14 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`; E1, E6 y E7 en `excepciones-skills-bd.md` | |

`usp_validar_sesion_operacion_interno` ya cumplía y no cambia. `usp_validar_carga_masiva_usuarios` está retirado (su archivo solo lo
borra) y no se toca.

Se conservan los textos que las pruebas buscan en las definiciones: `DEC_020` y `usp_sincronizar_usuario_interno` en
`usp_crear_decano` y `usp_crear_coordinador` (sin el literal del tipo de documento), `SesionSolicitud` en `usp_crear_sesion_interno`, y
`usp_generar_sesiones_grupo` sigue sin `INSERT ... EXEC` ni tablas `#`.

El manifiesto LB-004D ya no coincidía con `test/test_lb004d_concurrency.ps1` desde el lote 1 (la prueba salió del gate y cambió sin
regenerar el manifiesto, que no verifica el CI); al regenerarlo en este lote vuelve a quedar al día.

Sin migración: el lote solo cambia cuerpos y comentarios de SP y agrega vistas; `deploy_schema.ps1` aplica todo `schema/views`.

## Diferencias observables (ninguna de negocio)

Ninguna: se comparó `sys.dm_exec_describe_first_result_set_for_object` antes y después en los 38 SP y los metadatos son idénticos.
En los dos internos que no tenían `TRY` (`usp_validar_valor_parametro_externo_interno`, `usp_validar_plazo_justificacion_interno`) y en
las fachadas de sesión el `CATCH` nuevo solo relanza, así que un error del motor llega al llamador igual que antes.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP y los manifiestos como estaban (las vistas nuevas quedan sin uso y se
pueden borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`. `lb004d-manifest.ps1 -Mode Verify` también pasa.
