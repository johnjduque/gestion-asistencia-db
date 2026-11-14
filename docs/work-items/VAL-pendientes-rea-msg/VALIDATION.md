---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-pendientes-rea-msg (BD) - VALIDATION

Fecha: 2026-11-13. Rama `fix/VAL-pendientes-rea-msg` sobre `origin/develop`. Sin Maven corriendo en paralelo.

## Compuerta de BD (instancia limpia y temporal)

Contenedor desechable SQL Server 2022 Developer con `MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS` (confirmado con
`SERVERPROPERTY('Collation')`), sin puerto publicado, clave generada en la corrida y nunca impresa; se borró al terminar. Mismo
orden que la CI (ver [VAL-oleada3-bd-pendientes/VALIDATION.md](../VAL-oleada3-bd-pendientes/VALIDATION.md)). La BD compartida de
desarrollo no se tocó (su colación no coincide y la migración 42 espera la unión).

| Dato | Valor |
| :--- | :--- |
| Inicio / fin | 2026-11-13 16:22:30 / 16:52:17 (UTC-5) |
| `deploy_schema.ps1` | rc 0 |
| `migrar.ps1 -Modo Baseline` / `-Modo Estado` | rc 0 / rc 0: `total=42 registradas=42 pendientes=0 deriva=0` |
| `TOTAL_EXPECTED` (ids críticos) | 622 (incluye los 3 ids nuevos `VAL_MSG03_*`) |
| `TOTAL_EXECUTED` / `PASSED` / `FAILED` | 800 / 799 / 0 |
| `SKIPPED` / `ALLOWED_SKIPPED` | 1 / 1 (`XACT_STATE_MINUS_ONE_RUNTIME`, el único permitido) |
| `CRITICAL_MISSING` / `SQLCMD_EXIT_CODE` / `SQL_ERROR_COUNT` / `UNAUTHORIZED_SKIPS` | 0 / 0 / 0 / 0 |
| Resultado | `DB GATE PASS`, rc 0; limpieza del fixture LB-004D rc 0 |

## Migración 42

En la misma instancia, después del despliegue (que ya incluye la semilla 63):

| Paso | Resultado |
| :--- | :--- |
| `test_val_mensajes_err_pendientes.sql` tras el despliegue | rc 0, 3 de 3 `TEST_PASS` |
| `42_val_mensajes_err_pendientes_down.sql` | rc 0, `MIGRACION 42 DOWN OK` |
| Misma prueba tras el down | rc 1, `TEST FAILED VAL_MSG03_01` (rojo esperado) |
| `42_..._up.sql` dos veces seguidas | rc 0 y rc 0 (idempotente) |
| Misma prueba tras el up | rc 0, 3 de 3 `TEST_PASS` |
| Texto con tildes | `ERR_ANTIVIRUS_NO_DISPONIBLE` = "El antivirus no está disponible; el archivo no se guardó. Intente de nuevo en unos minutos." |
| `migrar.ps1 -Modo Estado` con la 42 en el repo | `MIGRAR_BASELINE 42_val_mensajes_err_pendientes`, `pendientes=0 deriva=0` |

## Verificaciones locales

| Verificación | Resultado |
| :--- | :--- |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11 culm001_d=85` |
| `scripts/lb004d-manifest.ps1 -Mode Verify` | `LB004D_MANIFEST_OK entries=9` |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=492` |
| `build-message-catalog.py --previo --check` (Infra) contra el fixture del backend | `OK ... coincide con los seeds (492 mensajes)` |

## Pendiente

- Aplicar la migración 42 a la BD compartida de desarrollo después de la unión (`scripts/migrar.ps1 -Modo Aplicar`).
- Sin push ni CI de GitHub.
