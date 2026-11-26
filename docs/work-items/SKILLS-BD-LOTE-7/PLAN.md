---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 7: estudiantes y matrícula en grupo

## Contexto

Lote 7 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 27 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 6. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió `test/test_skills_lote7_caracterizacion.sql`
(7 casos sobre los internos de estudiante que no tenían prueba directa) y se corrió sobre el código previo (pasaron los 7); después
del refactor pasan los 7, igual que las pruebas de dominio de los 27 SP (retiro, reactivación, HU008, IDENT-001, matrícula manual,
propiedad de transacción, directorio y consultas de estudiante).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Internos | `usp_validar_programa_comun_estudiante_grupo_interno`, `usp_validar_estudiante_en_programa_interno`, `usp_sincronizar_estudiante_interno`, `usp_registrar_estudiante_en_programa_interno`, `usp_registrar_estudiante_en_grupo_interno`, `usp_reactivar_matricula_retirada_interno` | Lecturas sin bloqueo por `uv_estudiante_programa`, `uv_estudiante_identidad`, `uv_estudiante_grupo` y la vista nueva; `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`. Las lecturas con `UPDLOCK, HOLDLOCK` siguen en la tabla |
| Internos sin cambio | `usp_validar_estudiante_exista_por_id_interno`, `usp_validar_registro_estudiante_en_grupo_interno` | Ya cumplían; la prueba del lote los cubre |
| Comandos | `usp_registrar_estudiante_en_grupo`, `usp_retirar_estudiante_grupo`, `usp_abrir_ventana_matricula_grupo`, `usp_cerrar_ventana_matricula_grupo`, `usp_actualizar_semestre_estudiante_programa` | Lecturas por vistas; `DECLARE` de los pasos a la cabecera; `IF` con `BEGIN/END`; bloqueos sobre `Grupo`, `EstudianteGrupo` y `TokenMatriculaGrupo` en la tabla |
| Consultas | 15 SP `usp_buscar_*`/`usp_consultar_*` de estudiantes | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Vista nueva | `schema/views/uv_estudiante_programa_semestre.sql` | `id`, `idEstudiante`, `idPrograma`, `semestreActual` de `EstudiantePrograma`. `uv_estudiante_programa` no expone `semestreActual` y la skill no permite cambiar la forma de una vista existente. Inventario de `transaccion-procedimiento.md`: 109 vistas |
| Pruebas | `test/test_skills_lote7_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 7 IDs nuevos `SKL7_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 7 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` | No hace falta excepción nueva |

Cada vista usada en lugar de una tabla se revisó: todas las uniones del camino van por FK `NOT NULL` (`uv_estudiante_identidad` y
`uv_docente_identidad` unen el rol con `uv_usuario`, que une `uv_tipo_identificacion`; `uv_periodo_academico` une `uv_institucion`;
las uniones opcionales de `uv_grupo` y `uv_programa` son `LEFT JOIN`), así que devuelven las mismas filas que la tabla.

Sin migración: el lote solo cambia cuerpos de SP y agrega una vista; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo
del Golden Path ni de los manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- `usp_cerrar_ventana_matricula_grupo` gana `SET XACT_ABORT ON` (fachada que muta). Sin errores del motor no cambia nada; con uno,
  la transacción se marca no confirmable en el acto, como en el resto de fachadas.
- `usp_consultar_directorio_estudiantes_paginado`: al leer el ámbito por vistas, el costo estimado del plan sobre la base semilla pasó
  de 0,164 a 0,241 (sin agregaciones nuevas; las uniones extra son búsquedas por clave). El tiempo medido es del mismo orden; se
  deja anotado por si en volumen real conviene revisarlo.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (la vista nueva queda sin uso y se puede borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
