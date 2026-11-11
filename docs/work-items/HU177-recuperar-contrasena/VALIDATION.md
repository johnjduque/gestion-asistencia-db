# HU177 — validación del retiro

| Comando | Resultado |
|---|---|
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre un contenedor SQL Server 2022 limpio (mismo orden que el job `DB Quality Gate CI/CD`), 2026-11-11 | `TOTAL_EXPECTED=564`, `TOTAL_EXECUTED=742`, `PASSED=741`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS`. Es el conteo anterior a HU177 (740) más el caso nuevo `HU177_RETIRO_MIG` |
| `scripts/freeze-manifest.ps1 -Mode Verify` (dentro del gate) | `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED`: el hash de `zz_foreign_keys.sql` vuelve al valor anterior |
| Migración `36_hu177_retiro_recuperacion_clave_up.sql` en la BD local de John, que tenía la 35 aplicada | Aplicada el 2026-11-11: ya no existen la tabla `TokenRecuperacionClave`, los cuatro SP, los mensajes `RCL_*`, los parámetros `RECUPERACION_CLAVE` ni la plantilla |
