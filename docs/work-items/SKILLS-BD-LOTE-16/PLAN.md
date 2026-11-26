---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 16: correcciones del code review

## Contexto

El 2026-11-26 se corrió `/code-review` sobre la rama larga `refactor/skills-bd` (lotes 0-15, comparada árbol a árbol con develop)
y sobre develop (`informes/CODE_REVIEW_RAMA_SKILLS-BD_2026-11-26.md` en la carpeta del proyecto). John pidió hacer las correcciones;
las de develop se aplican sobre esta rama, no sobre develop. Regla del lote: el comportamiento que ve la app no cambia y no se editan
los skills de BD.

## Cambios

| Hallazgo | Qué se hizo |
|---|---|
| Rama 1 (seguridad): las 32 vistas finas nuevas quedaban con `SELECT` para el backend por el grant genérico de `uv_*` y pasaban por encima del `DENY` de `dbo.ArchivoSoporte` | `schema/security/zz_rol_asistencias_runtime_skills_bd_vistas_internas.sql`: `DENY SELECT` de las 32 vistas al rol runtime (el backend no usa ninguna; los SP las leen por encadenamiento de propiedad). Excepción E3 actualizada. Pruebas `SKL16_S01` y `SKL16_S02` |
| Rama 2: `scripts/tests/test_migracion_13_culm001_a.ps1` apuntaba al archivo retirado `usp_internal_reactivar_matricula_retirada.sql` | Se quita de la paridad T-13 (lo cubre `test_skills_lote2_migracion_78.ps1`); el conteo del nombre viejo tras el down de la 13 se conserva |
| Rama 3: los down de las migraciones 11, 13, 15, 16, 17, 20, 21, 53 y 68 no borraban los 16 núcleos renombrados | Cada down borra también el nombre nuevo (`DROP PROCEDURE IF EXISTS`). Las pruebas de down de la 15, la 20 y la 21 lo comprueban. Manifiesto CULM-001 D regenerado para 20, 21 y 68 |
| Rama 4: 4 SP públicos de token (`usp_matricular_estudiante_por_token`, `usp_registrar_estudiante_por_token_publico`, `usp_rotar_token_matricula_grupo`, `usp_rotar_token_matricula_automatico`) ocultaban el error con la transacción del llamador condenada | Su `CATCH` relanza con `IF XACT_STATE() = -1 AND @@TRANCOUNT > 0 THROW;`, como el resto de SP públicos. Prueba `SKL16_T01` |
| Rama 5: `usp_marcar_ausentes_toma_interno` agregaba `UPDLOCK, HOLDLOCK` a lecturas que antes no bloqueaban | Esas lecturas vuelven a ir sin bloqueo, por las vistas finas; quedan los 3 bloqueos de antes. Prueba `SKL16_B01` |
| Rama 6: comentario de `usp_cerrar_tomas_vencidas` decía que el detalle del error quedaba guardado | Comentario corregido (el job no lo devuelve ni lo registra, igual que antes); `@estadoResultado` se reinicia por toma. Además (nota del security review) `@cancelada` vuelve a ser un `EXISTS` sobre la cancelación, ahora por `uv_sesion_cancelacion` |
| Rama 7: `usp_obtener_mensaje_catalogo` con código NULL dependía de `GENERAL/CADENA_VACIA` | `IIF(@p_codigo IS NULL, '', TRIM(@p_codigo))`, sin leer tablas. Prueba `SKL16_M01` |
| Develop 1: `usp_registrar_asistencia_por_token` confirmaba lo escrito cuando el registro fallaba (cabecera `Asistencia` huérfana) y no volvía al punto de guardado con transacción del llamador | Un fallo revierte la transacción propia; con transacción del llamador vuelve al punto de guardado si el núcleo llegó a escribir (los rechazos previos no escriben y así un llamador con `INSERT-EXEC` no recibe el error 3915). Prueba `SKL16_A01` |
| Develop 2: la migración 76 y las pistas de rendimiento (RECOMPILE, NO_PERFORMANCE_SPOOL, FORCESEEK) no tenían prueba | `test/test_perf_migracion_76.ps1` + `.sql`: `PERF_HINTS_KPI` y `PERF_MIG76_UP_DOWN_UP`, registradas en `test_summary.ps1` |
| Develop 3: el marcador de la migración 77 revisaba 1 de los 11 parámetros | Nuevo marcador `existe: false`: ninguno de los 11 sigue editable |
| Develop 4: `SELECT TOP 1` sin `ORDER BY` al elegir la matrícula activa | `ORDER BY eg.id` en `usp_registrar_asistencia_por_token` y en `usp_sincronizar_asistencia_estudiante_interno` (las dos eligen la misma fila) |

Las pruebas nuevas están en `test/test_skills_lote16_correcciones.sql` (registrada en `test_suite.sql` después del lote 15) y en
`test/test_perf_migracion_76.*`; sus ids están en `test_summary.ps1`.

## Verificación

- Gate local completo (`freeze-manifest.ps1 -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`, `test_summary.ps1`): ver el commit del lote.
