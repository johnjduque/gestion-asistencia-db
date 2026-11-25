---
status: active
type: work-item
scope: db-tests
owner: db-team
last-reviewed: 2026-11-25
---

# PLAN — SKILLS-BD lote 1: pruebas faltantes y CI (`cobertura-pruebas-objetos-bd`)

## Contexto

La auditoría del 2026-11-25 encontró objetos sin prueba directa y pruebas que el gate no ejecutaba. Este lote solo toca pruebas, el runner y la documentación, sin cambiar ningún objeto de `schema/`. Además deja la red de caracterización que necesitan los lotes de refactor siguientes.

## Cambios

| Cambio | Detalle |
|---|---|
| `test/test_skills_lote1_cobertura.sql` (nuevo, en `test_suite.sql`) | Caracterización de 5 funciones (`ufn_validar_correo`, `ufn_validar_numero`, `ufn_validar_texto`, `ufn_obtener_identidad_usuario_json`, `ufn_programas_ambito_ejecutor`), 10 vistas sin prueba (forma y contenido) y 2 núcleos (`usp_internal_asociar_asignatura_plan`, `usp_internal_cerrar_toma`). 15 escenarios `SKL1_*`, todos en una transacción revertida. |
| `test_summary.ps1` | Ejecuta en el gate `test_docente_programa_concurrencia.ps1` (T-091-13) y `test_lb004d_concurrency.ps1` (LB-004D W1, W2 y CULM001_D2_11). Antes no los corría nadie. Registra los 20 IDs nuevos como esperados. |
| `test/test_culm001_b2nm_deploy_limpio.ps1`, `test/test_culm001_b2nm_migracion.ps1` | Se marcan como **MANUAL** en su cabecera: son verificaciones históricas de las migraciones 17 y 18. Una necesita un backup que el CI no tiene; la otra repite lo que el gate ya hace al desplegar desde cero. |
| `docs/arquitectura/transaccion-procedimiento.md` | Inventario vigente: 306 SP (208 públicos, 82 `_interno` y 16 `usp_internal_*`), 106 vistas, 30 funciones, 75 tablas y 1 trigger. |

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1` (Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
- `develop` (referencia): `DB GATE PASS`, 1127/1127.
- Este lote: `DB GATE PASS` (ver el cierre del lote).
