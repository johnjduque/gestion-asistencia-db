# DEDUP — validación

| Comando | Resultado |
|---|---|
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre un contenedor SQL Server 2022 limpio (mismo orden que el job `DB Quality Gate CI/CD`), 2026-11-10 | `TOTAL_EXPECTED=563`, `TOTAL_EXECUTED=741`, `PASSED=740`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS`. Pasa el caso nuevo `DVS_MIG_UP_DOWN_UP` |
| Pruebas funcionales existentes de los tres procedimientos (dentro de la compuerta): sesiones manuales (SMN), destinatarios de sesión cancelada (B.1) y solicitud de sesión (MRM) | Pasan sin cambios |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK`: ningún objeto congelado cambia |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=286` |

## Sin validar

- El porcentaje de duplicación en SonarCloud. Solo se conoce cuando SonarCloud analiza `develop` después de unir el PR; el análisis no se puede correr en local.
