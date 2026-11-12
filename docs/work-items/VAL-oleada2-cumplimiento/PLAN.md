---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-12
---

# VAL-oleada2-cumplimiento (BD) - PLAN

Fecha: 2026-11-12. Agente T (cadena de suministro y CI). Primero se tocó solo `.github/` (compuerta de BD en curso); después, con el repo libre, se agregaron la migración 40 y la semilla.
Ítems de `informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`: TRI-04, TRI-06, TRI-07, SEC-05, SEC-08, EST-05, EST-09.

| Ítem | Cambio | Archivo |
| :--- | :--- | :--- |
| TRI-04 | Trivy en dos pasos: inventario SARIF (`exit-code 0`) subido a Code Scanning y al artifact `db-quality-evidence`, y compuerta `exit-code 1` con `HIGH,CRITICAL`, `ignore-unfixed: true`, escáneres `vuln,misconfig,secret`. Trivy 0.74.0 fijado; acción fijada por SHA (v0.36.0). El paso de compuerta conserva `id: trivy-scan`, así el resumen del job sigue leyendo su resultado | `.github/workflows/ci.yml` |
| EST-05 | Sonar ya esperaba el gate (`sonar.qualitygate.wait=true`). Se cambia `SonarSource/sonarcloud-github-action@master` (etiqueta mutable, acción deprecada) por `SonarSource/sonarqube-scan-action` v8.4.1 fijada por SHA; usa `sonar-project.properties` como antes | `.github/workflows/ci.yml` |
| SEC-05 / SEC-08 | Job `Gitleaks Secret Scan` (binario 8.30.1 con SHA-256 fijado, solo commits del PR/push) y `.github/gitleaks.toml` | `.github/workflows/ci.yml`, `.github/gitleaks.toml` |
| EST-09 | Dependabot semanal: docker-compose y github-actions hacia `develop` | `.github/dependabot.yml` |
| Fijado | checkout v7.0.1, upload-artifact v7.0.2, upload-sarif v4.39.3 por SHA; `permissions: contents: read` a nivel de workflow y `security-events: write` solo en el job | `.github/workflows/ci.yml` |

El backend ahora hace checkout de este repo (rama `develop`) y corre `deploy_schema.ps1` en su `integration.yml` (PRU-04): cambiar la firma de ese script rompe el CI del backend.

## Migración 40: PAR-06 y ROL-12

Ítems: PAR-06, ROL-12 (hallazgo H-03).

| Ítem | Cambio | Archivo |
| :--- | :--- | :--- |
| PAR-06 | Parámetro `AUDITORIA`/`RANGO_MAXIMO_DIAS` = 90 (`INT`, valor por defecto 90). Fila en `CatalogoParametroEdicion` con rango 1..366 y `esEditable = 0` (el grupo `AUDITORIA` está en `PARAMETROS/GRUPOS_NO_EDITABLES`, igual que en el backend). | `migrations/40_val_parametro_rango_auditoria_up.sql`, `schema/seed/57_val_parametro_rango_auditoria.sql` |
| ROL-12 | Ámbito de las cuentas semilla: el decano `decano.ingenieria@uco.edu.co` queda como titular de la Facultad de Ingenieria (`Facultad.decano`) y el coordinador `coordinador.sistemas@uco.edu.co` coordina Ingenieria de Sistemas (`Programa.coordinador`) y conserva su facultad (`Coordinador.facultad`); es lo mismo que dejan `usp_crear_decano_interno` y `usp_crear_coordinador_interno`. Idempotente: solo actúa si las filas semilla existen y la cuenta no tiene ese ámbito (en un despliegue limpio el coordinador quedaba con `facultad` NULL). | `migrations/40_...up.sql`, `schema/seed/57_val_ambito_cuentas_semilla.sql` |
| Down | Retira el parámetro y su fila de edicion. No revierte el ámbito (reintroduciría H-03). | `migrations/40_val_parametro_rango_auditoria_down.sql` |
| Prueba | `VAL_PAR06_01`, `VAL_PAR06_02`, `VAL_ROL12_01`, `VAL_ROL12_02`, `VAL_OLEADA2_TRANCOUNT_ZERO`, registradas en `test_suite.sql` y `test_summary.ps1` | `test/test_val_oleada2_parametro_y_ambito.sql` |
| Manifiesto | 4 archivos nuevos en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | `docs/contracts/` |
| Documentación | Fila del parámetro en el catálogo | `docs/catalogos/catalogo-parametros.md` |

Nota: las cuentas del laboratorio `uco-decano` y `uco-coordinador` se mapean a estas cuentas semilla; si la base del laboratorio fue creada antes de este cambio, se corrige aplicando la migración 40.
