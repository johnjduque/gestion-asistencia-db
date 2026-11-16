# VAL-oleada9 (BD): mensaje ERR_ALMACENAMIENTO_NO_DISPONIBLE

Fecha: 2026-11-15. Rama `fix/VAL-oleada9-mensaje-almacenamiento` desde `develop` 12e71eb. Origen: REA-02 de la lista de
chequeo de validación. El backend (`alejovh12/AsistenciasUCO`, `fix/VAL-oleada9-backend`) responde 503 con este código cuando
MinIO no responde al subir o descargar un soporte; en el laboratorio respondía 500 `INTERNAL_ERROR`.

## Cambios

| Archivo | Cambio |
| :--- | :--- |
| `schema/seed/63_val_mensajes_err_pendientes.sql` | Fila de usuario (TECHNICAL_ERROR, ALTO, 99 caracteres, sin marcadores) y fila técnica |
| `migrations/47_val_mensaje_almacenamiento_up.sql` / `_down.sql` | Siembra o retira el mensaje en bases existentes (MERGE idempotente) |
| `scripts/migrar-marcadores.json` | Marcador de la migración 47 (fila en `CatalogoMensajeUsuario`) |
| `test/test_val_oleada9_mensaje_almacenamiento.sql` y `test_suite.sql` | `VAL_REA02_01` (existe, tipo, mensaje técnico, 10–100 caracteres) y `VAL_REA02_TRANCOUNT_ZERO` |
| `docs/catalogos/catalogo-mensajes.md` | Fila del código |
| `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | Hash de la semilla 63 y de los marcadores |

## Evidencia (BD del laboratorio, `sql_server_asistencias`)

| Paso | Resultado |
| :--- | :--- |
| Prueba antes de la 47 | `TEST FAILED VAL_REA02_01` (RED) |
| `47_up` dos veces | Completa las dos veces (idempotente) |
| Prueba | `TEST_PASS:VAL_REA02_01_MENSAJE_ALMACENAMIENTO`, `TEST_PASS:VAL_REA02_TRANCOUNT_ZERO` |
| `47_down` y prueba | Retira la fila; la prueba vuelve a fallar |
| `47_up` final y prueba | PASS |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK` |

La migración se aplicó con `sqlcmd -i` y no se registró en `MigracionAplicada`. Antes se intentó `scripts/migrar.ps1 -Modo
Aplicar`, que re-ejecutó las migraciones 05–12 sobre la base del laboratorio (registro vacío tras `deploy_schema.ps1`); los
efectos se revirtieron (detalle en `VALIDATION.md` de `VAL-oleada9-backend` del backend).

## No ejecutado

- **Compuerta completa de BD** (deploy limpio, `test_summary.ps1` y `test_val_migrar_detectar.ps1`): queda para el CI del PR.
