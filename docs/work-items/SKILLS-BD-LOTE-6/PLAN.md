---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 6: asignaturas y planes de estudio

## Contexto

Lote 6 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 13 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 5. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió `test/test_skills_lote6_caracterizacion.sql`
(`usp_validar_gestion_asignatura_coordinador_interno` no tenía prueba directa) y se corrió sobre el código previo (los 4 casos
pasaron); después del refactor pasan los 4, igual que las pruebas de dominio de los 13 SP.

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Validadores | `usp_validar_asignatura_activa_interno`, `usp_validar_gestion_asignatura_coordinador_interno` | Lecturas sin bloqueo por `uv_asignatura`, `uv_plan_estudio` y `uv_asignatura_plan_estudio`; `IF` con `BEGIN/END`, `PASO n`; el primero gana `TRY/CATCH` con `SYS_001` que relanza si hay transacción abierta. La lectura con `UPDLOCK, HOLDLOCK` sigue en la tabla |
| Fachadas de plan | `usp_agregar_semestre_plan_estudio`, `usp_quitar_semestre_plan_estudio`, `usp_cambiar_estado_plan_estudio`, `usp_registrar_o_actualizar_plan_estudio` | Lecturas por `uv_plan_estudio`, `uv_semestre_plan_estudio`, `uv_semestre` y `uv_asignatura_plan_estudio`; los bloqueos (`PlanEstudio`, `Programa`) siguen en la tabla; `IF` con `BEGIN/END` y `DECLARE` del `CATCH` a la cabecera |
| Fachada de asignatura | `usp_toggle_estado_asignatura` | `COALESCE` sobre variable cambiado por un `IIF` equivalente; `IF` con `BEGIN/END`; `PASO n` |
| Consultas | `usp_consultar_asignaturas_asociables_paginado`, `usp_consultar_asignaturas_coordinador_paginado`, `usp_consultar_asignaturas_plan_paginado`, `usp_consultar_planes_estudio_programa_paginado`, `usp_buscar_asignaturas_paginado`, `usp_consultar_componentes_formacion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza (como en los lotes anteriores) |
| Pruebas | `test/test_skills_lote6_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 4 IDs nuevos `SKL6_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 6 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | Sin vistas nuevas (el inventario de `transaccion-procedimiento.md` no cambia); no hace falta excepción nueva |

Cada vista usada en lugar de una tabla se revisó: todas las uniones del camino van por FK `NOT NULL` (`uv_plan_estudio` une
`PlanEstudio` con `uv_programa`, que une `uv_facultad` y `uv_institucion`; las uniones opcionales de `uv_programa` son `LEFT JOIN`), así
que devuelven las mismas filas que la tabla.

Sin migración: el lote solo cambia cuerpos de SP; `deploy_schema.ps1` lo aplica todo. Ningún archivo del Golden Path ni de los
manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- Un error del motor dentro de `usp_validar_asignatura_activa_interno` sin transacción abierta devuelve `SYS_001` en el triplete en vez
  de salir como excepción. `usp_crear_grupo` lo invoca con transacción abierta (relanza, como antes). `usp_asociar_asignatura_plan`
  lo invoca antes de abrir la suya: antes la excepción caía en su propio `CATCH`, que responde `SYS_001`; ahora recibe el triplete
  `SYS_001` y lo devuelve. La respuesta final es la misma (`SYS_001`).

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban.

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
