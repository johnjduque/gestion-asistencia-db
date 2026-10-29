---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — MAINT-PRUEBAS-HUERFANAS: registrar en el gate las pruebas que nunca se ejecutaban

## Hallazgo

La auditoría de la BD contra los skills (2026-10-28) encontró cuatro archivos en `test/` que no estaban registrados en `test_suite.sql` ni en otro runner. El `DB Quality Gate` no los ejecutaba:

| Prueba | Cubre | Autor |
|---|---|---|
| `test_usp_actualizar_coordinador.sql` | `usp_actualizar_coordinador` (HU121) | Sergio |
| `test_usp_cambiar_estado_coordinador.sql` | `usp_cambiar_estado_coordinador` (HU122) | Sergio |
| `test_hu121_hu122_esquema_coordinador.sql` | Columnas `estado`/`facultad` de `Coordinador`, `uv_coordinador` | Sergio |
| `test_sec_baseline_identidad_externa.sql` | `usp_vincular_identidad_externa` / `usp_revocar_identidad_externa` | Alejo |

## Cambio

1. Registro de las cuatro pruebas en `test_suite.sql`, después de `test_usp_crear_coordinador.sql`.
2. Al ejecutarlas por primera vez, `T-DDL-02` falló: el coordinador sembrado tenía `Coordinador.facultad` en NULL.
   - **Causa:** `schema/tables/Coordinador.sql` rellena `facultad` desde el programa al crear la columna, pero en un despliegue limpio el coordinador (seed 12) y el programa (seed 13) se siembran **después**.
   - **Alcance:** en las BD que ejecutaron `migrations/05_*` el dato ya estaba relleno. En una BD nueva, el coordinador sembrado quedaba sin facultad para el ámbito del decano.
3. Seed nuevo `schema/seed/25_coordinador_facultad_desde_programa.sql`.
   - Repite el relleno idempotente de la tabla y de la migración 05 (`UPDATE ... WHERE facultad IS NULL`), ahora después de sembrar los programas.
   - Es aditivo: no modifica tablas, SP, vistas ni objetos congelados.

No hay cambios en el backend ni en el frontend.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29):

- **Antes del seed 25:** `TEST FAILED T-DDL-02`. La suite se detuvo y dejó `CRITICAL_MISSING=44`.
- **Con el seed 25:**
  - `TOTAL_EXECUTED=378`, `PASSED=377`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS`.
  - `freeze-manifest -Mode Verify`: OK.
- **Escenarios nuevos en el gate:**
  - `COORDINATOR_UPDATE_*` (4) y `COORDINATOR_STATE_*` (4);
  - `COORDINATOR_SCHEMA_COLUMNS`, `COORDINATOR_VIEW_COLUMNS` y `COORDINATOR_CREATE_SETS_FACULTY`;
  - `EXTERNAL_IDENTITY_LINK`, `EXTERNAL_IDENTITY_CONFLICTS` y `EXTERNAL_IDENTITY_REVOCATION`.

## Rollback

Revertir el commit: se quitan las cuatro líneas de `test_suite.sql` y se borra el seed 25. El seed solo rellena NULL, así que no hay datos que deshacer.
