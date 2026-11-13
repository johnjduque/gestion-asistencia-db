---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-oleada3-mensajes (BD) - PLAN

Fecha: 2026-11-13. Origen: `informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`, ítems MSG-05 (mensajes quemados del backend) y
MSG-03 (catálogo de MessageUcoLab al día con la BD). Rama local `fix/VAL-oleada3-mensajes-catalogo` desde `origin/develop`.

## Migración 41: mensajes de usuario del backend

El backend dejó de escribir en el código los textos de sus validaciones (400), accesos (403), recursos inexistentes (404) y
funcionalidad no disponible (501): conserva el código público de la respuesta (`VALIDATION_ERROR`, `FORBIDDEN`,
`RESOURCE_NOT_FOUND`, `FEATURE_UNAVAILABLE`, `ERR_CAMPO_OBLIGATORIO`, `ERR_FECHA_HORA_INVALIDA`) y busca el texto en el catálogo
por un código de mensaje propio (enum `MensajeUsuarioErrorCode` del backend).

| Ítem | Cambio | Archivo |
| :--- | :--- | :--- |
| MSG-05 | 107 mensajes nuevos en `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico`: `VAL_APP_001..075` (`VALIDATION_ERROR`, `BAJO`), `ACC_APP_001..017` (`SECURITY_ERROR`, `ALTO`), `NOF_APP_001..014` (`BUSINESS_ERROR`, `MEDIO`), `DIS_APP_001` (`BUSINESS_ERROR`, `MEDIO`). Texto con tildes; los mensajes con datos llevan marcadores `{}` (VAL_APP_022, 032, 034, 039, 046, 069 y 070). El técnico indica el código de respuesta y el texto original del backend. | `migrations/41_val_mensajes_aplicacion_up.sql`, `schema/seed/62_val_mensajes_aplicacion.sql` |
| Reutilizados | `GEN_001`, `PER_001`, `PAG_001` y `KPI_001` ya existían con el mismo significado: el backend los usa como código de mensaje y no se duplican. | — |
| Down | Borra las filas `VAL_APP_*`, `ACC_APP_*`, `NOF_APP_*` y `DIS_APP_*` de ambos catálogos (el backend vuelve a su texto de respaldo). | `migrations/41_val_mensajes_aplicacion_down.sql` |
| Prueba | `VAL_MSG05_01_MENSAJES_SEMBRADOS`, `VAL_MSG05_02_TEXTOS_Y_MARCADORES`, `VAL_OLEADA3_MSG_TRANCOUNT_ZERO`, registradas en `test_suite.sql` y `test_summary.ps1` | `test/test_val_oleada3_mensajes_aplicacion.sql` |
| Manifiesto | 3 archivos nuevos (migración up/down y semilla) en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` (`-Mode UpdateCulm001D`) | `docs/contracts/` |
| Documentación | `docs/catalogos/catalogo-mensajes.md` regenerado (291 → 398 códigos) con `scripts/generar-catalogo-mensajes.ps1` | `docs/catalogos/` |

Sin tablas, vistas ni procedimientos nuevos; solo filas de catálogo (MERGE idempotente por código). Números libres usados: migración
41 (la última era 40) y semilla 62 (la última era 61).

## MSG-03

Los seeds son la fuente del catálogo de MessageUcoLab: el fixture del backend (`catalogo-mensajes-usuario.psv`) se regeneró desde
`schema/seed` con `AsistenciasUCO-Infra/components/messages/build-message-catalog.py --previo` (398 códigos). La importación a una
instancia viva de MessageUcoLab (Excel `--xlsx`) es operación del ambiente.
