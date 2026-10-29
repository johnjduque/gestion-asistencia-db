---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# VALIDATION — HU006-perfil-usuario

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-27 | `TEST_PASS:HU006_PERFIL_*` (3), `TOTAL_EXECUTED=343`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`, exit 0 |
| GitHub Actions `DB Quality Gate CI/CD` | Pendiente: rama en commits locales, sin subir |

## Incidencia corregida durante la validación

La primera corrida falló porque la prueba insertaba `NULL` en `Usuario.segundoNombre` y `segundoApellido`, que son NOT NULL. Se corrigió el fixture para usar cadena vacía. El SP ya trataba las cadenas vacías con `NULLIF(TRIM(...))` al armar `nombreCompleto`.

## Pendientes

- Desviación: no hay commit RED separado.
- Limitación: falta la prueba manual en pantalla (MV-008).
