# HU177 — validación

| Comando | Resultado |
|---|---|
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre un contenedor SQL Server 2022 limpio (mismo orden que el job `DB Quality Gate CI/CD`), 2026-11-11 | `TOTAL_EXPECTED=575`, `TOTAL_EXECUTED=753`, `PASSED=752`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS`. Pasan los 12 casos nuevos: los 11 de `test_hu177_recuperacion_clave.sql` y `HU177_MIG_UP_DOWN_UP` |
| `scripts/freeze-manifest.ps1 -Mode Verify` (dentro del gate) | `FREEZE_MANIFEST_OK`, después de actualizar el hash de `schema/tables/zz_foreign_keys.sql` con `-Mode UpdateCulm001D` |
| `scripts/generar-catalogo-mensajes.ps1` | `CATALOGO_MENSAJES_GENERADO codigos=289` (entran `RCL_001`, `RCL_002` y `RCL_003`) |
| Migración `35_hu177_recuperacion_clave_up.sql` y `test/test_hu177_recuperacion_clave.sql` en la BD local de John | Aplicada el 2026-11-11; los 11 casos pasan y la transacción de la prueba se revierte |

## Corrida descartada

La primera corrida de la compuerta (2026-11-11) terminó `DB GATE INCOMPLETE` por dos causas ajenas a la lógica de HU177:

- `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED` faltó porque el hash de `zz_foreign_keys.sql` aún no estaba actualizado en el manifiesto. Se corrigió con el modo `UpdateCulm001D` del script.
- `CULM001_B2_SEG_02_FIXTURES_REPETIBLES` falló con un error 500 del API de Docker: el equipo estaba saturado porque corrían a la vez las pruebas del backend. Repetida la compuerta sin otra carga, pasa.

## Sin validar

- El porcentaje de duplicación en SonarCloud: solo se conoce cuando SonarCloud analiza el PR. Los SP nuevos se escribieron compactos para no repetir los de IDENT-001.
