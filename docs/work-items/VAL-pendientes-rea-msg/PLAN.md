---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-pendientes-rea-msg (BD) - PLAN

Fecha: 2026-11-13. Rama local `fix/VAL-pendientes-rea-msg` desde `origin/develop`. Origen: deuda MSG-03 de la oleada 3 (93
códigos `ERR_*` que el backend lanza y que no tenían fila en el catálogo de mensajes; lista en el backend,
`src/test/resources/messageucolab/codigos-error-sin-catalogo.txt`) y hallazgo H3 de la prueba de carga (antivirus caído →
503 con código de catálogo). Pareja en el backend: rama del mismo nombre.

## Migración 42: mensajes `ERR_*` del backend

| Ítem | Cambio | Archivo |
| :--- | :--- | :--- |
| MSG-03 | 94 filas nuevas en `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico`: los 93 `ERR_*` de la deuda (con `ERR_CORREO_REQUERIDO_MATRICULA` en lugar de `FIELD_REQUIRED`, ver abajo) más `ERR_ANTIVIRUS_NO_DISPONIBLE` (H3). Tipos según el error del backend: validación `VALIDATION_ERROR`/`BAJO` (400), conflicto o inexistente `BUSINESS_ERROR`/`MEDIO` (409/404), acceso `SECURITY_ERROR`/`ALTO` (403), técnico o dependencia caída `TECHNICAL_ERROR`/`ALTO` (500/503). Texto de usuario con tildes y sin marcadores `{}`; el técnico indica el tipo, el enum de origen y el texto. | `migrations/42_val_mensajes_err_pendientes_up.sql`, `schema/seed/63_val_mensajes_err_pendientes.sql` |
| `FIELD_REQUIRED` | No se siembra: es el código genérico de campo obligatorio. El backend busca el texto de la matrícula sin correo por `ERR_CORREO_REQUERIDO_MATRICULA` y la respuesta conserva `FIELD_REQUIRED`. | — |
| Down | Borra exactamente esos 94 códigos de ambos catálogos (el backend vuelve al texto de respaldo de su enum). | `migrations/42_val_mensajes_err_pendientes_down.sql` |
| Prueba | `VAL_MSG03_01_MENSAJES_SEMBRADOS`, `VAL_MSG03_02_TEXTOS_Y_TIPOS`, `VAL_MSG03_TRANCOUNT_ZERO`, registradas en `test_suite.sql` y en los ids críticos de `test_summary.ps1` | `test/test_val_mensajes_err_pendientes.sql` |
| Manifiesto | 3 archivos nuevos en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` (`freeze-manifest.ps1 -Mode UpdateCulm001D`) | `docs/contracts/` |
| Documentación | `docs/catalogos/catalogo-mensajes.md` regenerado (398 → 492 códigos) con `scripts/generar-catalogo-mensajes.ps1` | `docs/catalogos/` |

Sin tablas, vistas ni procedimientos nuevos; solo filas de catálogo (MERGE idempotente por código), igual que la migración 41.
Números libres usados: migración 42 (la última era 41) y semilla 63 (la última era 62).

Tres textos se acortaron a 100 caracteres o menos (límite de la plantilla de MessageUcoLab):
`ERR_PASSWORD_POLITICA_INVALIDA`, `ERR_PERSONA_YA_REGISTRADA` y `ERR_ANTIVIRUS_NO_DISPONIBLE`.

## Aplicación

- No se aplica a la BD compartida de desarrollo: espera la unión. Después: `scripts/migrar.ps1 -Modo Aplicar` (idempotente).
- Catálogo de MessageUcoLab: el fixture del backend se regeneró desde estos seeds; importar a una instancia viva es operación del
  ambiente.
