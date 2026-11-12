---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-12
---

# VAL-oleada2-cumplimiento (BD) - VALIDATION

Fecha: 2026-11-12.

| Prueba | Resultado |
| :--- | :--- |
| `rhysd/actionlint:1.7.12` sobre `.github/workflows/ci.yml` (incluye shellcheck) | 0 hallazgos |
| Parseo YAML (js-yaml) de `ci.yml` y `dependabot.yml` | OK |
| Trivy local `aquasec/trivy:0.74.0 fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --ignore-unfixed` sobre el árbol rastreado | 0 hallazgos (TRI-07: 0 HIGH/CRITICAL). No hace falta `.trivyignore` |
| gitleaks 8.30.1 `dir` sin configuración / con `.github/gitleaks.toml` | 1 falso positivo (identificador de prueba `CULM001_B2_QR_..._TOKEN_Y_PIN` en `test_summary.ps1`) / 0 |
| Compuerta de BD (`test_summary.ps1`) | No corrida por el agente T (la corre John) |
| gitleaks con configuración en modo `git`: rango `HEAD~5..HEAD` / historial completo (636 commits) | rc 0 / 1 hallazgo en una versión vieja de `sonar-project.properties` (verificar que ese token de Sonar esté revocado) |
| Workflow en GitHub | No ejecutado; la primera corrida del PR es la evidencia |

Historial: gitleaks escanea solo los commits del PR o del push. Los valores viejos del historial quedaron invalidados con la rotación de credenciales y no se reescribe el historial.

## Migración 40: PAR-06 y ROL-12

| Prueba | Resultado |
| :--- | :--- |
| `test_val_oleada2_parametro_y_ambito.sql` antes de aplicar la migración 40 | Falla en `VAL_PAR06_01` (rojo esperado) |
| Migración 40 UP a la BD local, dos veces seguidas | OK, idempotente |
| Misma prueba después | 5 de 5 `TEST_PASS` (PAR06_01, PAR06_02, ROL12_01, ROL12_02, TRANCOUNT) |
| Down + semillas 57 + prueba | Parámetro retirado y restablecido por las semillas; 5 de 5 |
| Coordinador sin `facultad`, migración 40 UP y prueba | Reasigna la facultad; 5 de 5 |
| `freeze-manifest.ps1 -Mode Verify` / `lb004d-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK ... culm001_d=77` / `LB004D_MANIFEST_OK entries=9` |
| Compuerta de BD completa | No corrida por el agente (la corre John) |
