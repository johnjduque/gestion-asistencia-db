---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 5: docentes y grupos

## Contexto

Lote 5 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 19 SP. Va en la rama larga
`refactor/skills-bd` (develop se devolvió al estado previo a los lotes el 2026-11-26). Regla del lote: **no cambia el comportamiento de
la app** (mismas firmas, mismos resultsets, mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió
`test/test_skills_lote5_caracterizacion.sql` y se corrió sobre el código de la rama (los 6 casos pasaron); después del refactor pasan
los 6.

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Núcleos y validadores de docente | `usp_validar_docente_vinculo_activo_programa_interno`, `usp_vincular_docente_programa_interno`, `usp_sincronizar_docente_interno`, `usp_validar_docente_exista_por_id_interno` | Lecturas por `uv_docente_programa` y `uv_docente_identidad`, `PASO n`; los dos primeros ganan `TRY/CATCH` con `SYS_001` que relanza si hay transacción abierta. La lectura con `UPDLOCK, HOLDLOCK` sigue en la tabla. `usp_validar_docente_exista_por_id_interno` ya cumplía |
| Validadores de grupo | `usp_validar_consulta_grupo_docente_titular_interno`, `usp_validar_cupo_disponible_grupo_interno` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`; el primero gana `TRY/CATCH` con el mismo criterio |
| Fachadas | `usp_vincular_docente_programa`, `usp_cambiar_estado_docente_programa`, `usp_actualizar_docente_programa`, `usp_crear_grupo`, `usp_actualizar_grupo` | `IF` de una sentencia con `BEGIN/END`, `DECLARE` del `CATCH` a la cabecera, lecturas sin bloqueo por vistas (`uv_docente_programa`, `uv_programa`, `uv_estado_estudiante_grupo`) |
| Consultas | `usp_consultar_audiencias_realtime_grupo`, `usp_consultar_candidatos_docente_programa`, `usp_consultar_docentes_facultad_paginado`, `usp_consultar_docentes_programa`, `usp_consultar_grupos_facultad_paginado`, `usp_consultar_grupos_paginado`, `usp_consultar_oferta_creacion_grupo_docente`, `usp_consultar_programas_grupo` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza (como en los lotes anteriores) |
| Pruebas | `test/test_skills_lote5_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 6 IDs nuevos `SKL5_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 5 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | Sin vistas nuevas (el inventario de `transaccion-procedimiento.md` no cambia); no hace falta excepción nueva |

Cada vista usada en lugar de una tabla se revisó: todas las uniones del camino van por FK `NOT NULL` (por ejemplo `uv_docente_programa`
une `DocentePrograma`, `uv_docente_identidad`, `uv_usuario`, `uv_programa`, `uv_facultad` y `uv_institucion`), así que devuelven las
mismas filas que la tabla.

Sin migración: el lote solo cambia cuerpos de SP; `deploy_schema.ps1` lo aplica todo. Ningún archivo del Golden Path ni de los
manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- Un error del motor dentro de `usp_validar_docente_vinculo_activo_programa_interno`, `usp_vincular_docente_programa_interno` o
  `usp_validar_consulta_grupo_docente_titular_interno` sin transacción abierta devuelve `SYS_001` en el triplete en vez de salir como
  excepción. Dentro de una transacción relanza igual que antes.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban.

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
