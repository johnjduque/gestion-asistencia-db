---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-25
---

# PLAN — SKILLS-BD lote 2: robustez de los núcleos y renombre `usp_internal_*` → `usp_*_interno` (D3)

## Contexto

Lote 2 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`). Corrige por completo los SP del lote (triplete
OUTPUT, `TRY/CATCH` con `SYS_001`, `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, sin `ISNULL/COALESCE` ni cursores, lecturas
por vistas) y aplica la decisión D3 de John: los 16 núcleos `usp_internal_*` pasan a `usp_<nombre>_interno`. Regla del lote: **no cambia
el comportamiento de la app** (firmas y resultsets de los SP públicos iguales, mismos códigos de rechazo y mismo flujo de error).

Decisión de John (2026-11-25, tarjeta de decisión): los ~25 llamadores de los núcleos renombrados solo cambian la llamada (nombre,
variables del triplete y su revisión). Su corrección completa queda en el lote de su dominio.

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Núcleos renombrados y corregidos (9) | `usp_cerrar_toma_interno`, `usp_marcar_ausentes_toma_interno`, `usp_resolver_token_asistencia_interno`, `usp_rotar_token_asistencia_interno`, `usp_resolver_token_matricula_interno`, `usp_rotar_token_matricula_interno`, `usp_asociar_asignatura_plan_interno`, `usp_asegurar_estudiante_programa_grupo_interno`, `usp_aplicar_festivos_grupos_interno` | Triplete OUTPUT (nuevo en los que no lo tenían), `TRY/CATCH` con `SYS_001` y relanzamiento si la transacción del llamador quedó condenada, catálogos por vistas, lecturas con bloqueo en la tabla, sin cursor |
| Núcleos solo renombrados (7) | `usp_aplicar_festivos_grupo_interno`, `usp_cancelar_sesiones_receso_interno`, `usp_cargar_dias_festivos_interno`, `usp_matricular_por_token_interno`, `usp_radicar_solicitud_revision_interno`, `usp_reactivar_matricula_retirada_interno`, `usp_validar_plazo_justificacion_interno` | Mismo cuerpo; cambian el nombre y las llamadas a los núcleos renombrados. Se corrigen en su lote de dominio |
| Internos de identidad y contacto | `usp_actualizar_nombres_usuario_interno`, `usp_registrar_auditoria_identidad_interno`, `usp_consultar_contacto_notificacion_interno` | Triplete OUTPUT opcional (los llamadores existentes no cambian), `TRY/CATCH`, `PASO n`; contacto lee `uv_usuario` |
| SP públicos del lote | `usp_cerrar_tomas_vencidas`, `usp_matricular_estudiante_por_token`, `usp_registrar_estudiante_por_token_publico`, `usp_rotar_token_matricula_automatico`, `usp_rotar_token_matricula_grupo`, `usp_crear_asignatura`, `usp_asociar_asignatura_plan`, `usp_actualizar_asignatura`, `usp_desvincular_asignatura_plan`, `usp_consultar_resumen_sesiones_grupo_docente`, `usp_previsualizar_horario_grupo`, `usp_radicar_solicitud_revision_asistencia_v4` | Corrección completa con la misma firma y el mismo resultset. Las consultas de lectura relanzan el error (mismo `THROW 51000`) |
| Llamadores (solo la llamada) | `usp_abrir_toma_asistencia`, `usp_cerrar_toma_asistencia`, `usp_registrar_asistencia_por_token`, `usp_rotar_token_asistencia_automatico`, `usp_rotar_token_asistencia_toma`, `usp_validar_token_matricula_publico`, `usp_aplicar_festivos_automatico`, `usp_aplicar_festivos_periodo`, `usp_aplicar_festivos_grupo`, `usp_actualizar_docente_programa`, `usp_corregir_identidad_usuario_interno`, `usp_actualizar_coordinador`, `usp_precargar_sesiones_grupo_interno`, `usp_generar_sesiones_grupo_v2`, `usp_crear_receso_academico`, `usp_cargar_dias_festivos`, `usp_cargar_dias_festivos_automatico`, `usp_registrar_estudiante_en_grupo_interno`, `usp_radicar_solicitud_revision_asistencia` (v1, v2, v3), `usp_validar_periodo_abierto_sesion_interno`, `usp_validar_programa_comun_estudiante_grupo_interno` | Nombre nuevo; donde el núcleo ganó el triplete, variables `@...Interno` y `THROW 52521..52532` si devuelve `@estadoInterno = 0` |
| Migración 78 | `migrations/78_skills_lote2_renombre_internos_up/down.sql` | Up: si corre antes de `deploy_schema.ps1` crea los nombres nuevos como copia y recompila a los llamadores; siempre borra los 16 viejos. Down: recrea los viejos como copia de los nuevos (con `DENY`). Marcadores en `scripts/migrar-marcadores.json` (también se actualizan los de la 20 y la 53, que apuntaban a nombres viejos) |
| Seguridad | `schema/security/rol_asistencias_runtime_*.sql` | `DENY EXECUTE` y comentarios con los nombres nuevos |
| Pruebas | `test/test_skills_lote2_caracterizacion.sql` (nuevo, en `test_suite.sql`), `test/test_skills_lote2_migracion_78.ps1/.sql` (nuevo, en `test_summary.ps1`) y las pruebas que llamaban a los nombres viejos | 9 IDs nuevos `SKL2_*`. `test_val_obs03_id_correlacion.sql` saca de la lista blanca los 5 internos que ahora declaran `@idCorrelacion`. Las pruebas de migraciones viejas (13, 15, 16, 20, 21, 37, ...) siguen usando los nombres viejos: prueban esos scripts tal como son |
| Manifiesto | `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | Rutas renombradas y hashes actualizados (`WORK_ITEM`). Ningún archivo de `DB_DEVELOP_FREEZE` ni del Golden Path cambia |
| Documentación | `excepciones-skills-bd.md` (E7), `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` (addendum del lote 2), `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, `transaccion-procedimiento.md` (inventario: 306 SP, 208 públicos y 98 `_interno`), runbook `ACTUALIZAR_BD_LOCAL_EXISTENTE.md` | |

## Contrato de error

- Un rechazo de negocio no cambia: mismo código, mismo `@estadoResultado` y mismo mensaje.
- Un error no controlado en un núcleo devuelve `@estadoResultado = 0` con `SYS_001`. Si la transacción del llamador quedó condenada
  (`XACT_STATE() = -1`), el núcleo relanza el error original, así que los llamadores con `XACT_ABORT ON` ven el mismo error que antes.
- Las consultas de lectura (`usp_consultar_resumen_sesiones_grupo_docente`, `usp_previsualizar_horario_grupo`) relanzan el error en su
  `CATCH`, igual que las lecturas paginadas corregidas en lotes anteriores.

## Actualizar una base local

`deploy_schema.ps1` y después `scripts/migrar.ps1 -Modo Aplicar` (la 78 borra los nombres viejos). Ver el runbook.

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
- `develop` (referencia, lote 1 cerrado): `DB GATE PASS`, 1143/1143.
- Este lote, primera corrida: 1128 de 1152. Fallaban las 24 pruebas de migraciones que componen `migrations/` (la 78 tenía un `EXEC (... + QUOTENAME(...))` inválido y buscaba `CREATE OR ALTER` en `OBJECT_DEFINITION`, que el motor guarda como `CREATE` seguido de espacios), y `VAL_MDET` por los marcadores de la 20 y la 53. Corregidos, las 24 pasan al volver a correrlas (`test_culm001_b2`, `d1`, `d2`, `pc_migracion_37`, `hu177_retiro`, `dedup_validaciones_sesion`, `mrm_*`, `sesiones_manuales_notificacion`, `val_migrar_detectar`, `skills_lote2_migracion_78`). Las pruebas de la 21 (`test_culm001_d2_migraciones.sql`, `test_culm001_d2_down_sin_confirmacion.sql`) corren primero el down de la 78 dentro de su transacción para recrear los nombres viejos que usan esos scripts.
