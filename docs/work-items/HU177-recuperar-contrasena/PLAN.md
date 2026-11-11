# HU177 — recuperar contraseña con enlace de un solo uso

## Decisión

John, 2026-11-11: HU177 se hace con un flujo propio de la aplicación, no con la opción `resetPasswordAllowed` de Keycloak. Sigue el mismo patrón que la verificación de correo (IDENT-001): un enlace de un solo uso que llega por correo, del que la base de datos solo guarda la huella SHA-256.

## Flujo

1. El usuario escribe su correo en la página pública "Recuperar contraseña". El backend llama a `usp_consultar_solicitud_recuperacion_clave`. La respuesta al usuario es siempre la misma (`RCL_001`), exista o no la cuenta.
2. Si el SP devuelve un usuario, el backend encola el aviso `RECUPERACION_CLAVE`. Al entregarlo, el canal de correo genera el token, llama a `usp_emitir_token_recuperacion_clave` con su hash y arma el enlace `/restablecer-clave#token=…`.
3. El usuario abre el enlace y escribe la contraseña nueva. El backend consulta el enlace sin consumirlo (`usp_consultar_token_recuperacion_clave`), valida la política de contraseñas, cambia la contraseña en el proveedor de identidad y por último consume el enlace (`usp_consumir_token_recuperacion_clave`).

La contraseña no vive en la base de datos: se cambia en el proveedor de identidad (Keycloak).

## Objetos nuevos

| Objeto | Qué hace |
|---|---|
| `dbo.TokenRecuperacionClave` | Un enlace por fila: usuario, hash del token, emisión, vencimiento, uso y revocación. Índice único filtrado: un solo enlace pendiente por usuario. FK a `Usuario` en `zz_foreign_keys.sql` |
| `usp_consultar_solicitud_recuperacion_clave(@correo, @idCorrelacion)` | Lectura, 0..1 fila (`idUsuario`, `primerNombre`, `correo`). Devuelve fila solo si el correo es de un único usuario activo y ya pasó la espera mínima desde el último enlace. No lanza |
| `usp_emitir_token_recuperacion_clave(@idUsuario, @tokenHash, @idCorrelacion)` | Canónico. Revoca el enlace pendiente y registra el nuevo con vigencia `ahora + TTL_MINUTOS`. `VCE_007` si el usuario no existe o no está activo |
| `usp_consultar_token_recuperacion_clave(@tokenHash, @idCorrelacion)` | Lectura, 0..1 fila (`idUsuario`). No consume. 0 filas para cualquier enlace que no sirve |
| `usp_consumir_token_recuperacion_clave(@tokenHash, @idCorrelacion)` | Canónico. Marca el uso en una sola sentencia (`UPDLOCK`): de dos intentos simultáneos gana uno. `RCL_003` si lo consumió, `RCL_002` para cualquier enlace que no sirve |

## Semillas

- Mensajes `RCL_001` (respuesta uniforme a la solicitud), `RCL_002` (enlace que no sirve) y `RCL_003` (contraseña actualizada).
- Parámetros `RECUPERACION_CLAVE/TTL_MINUTOS` (60) y `RECUPERACION_CLAVE/REENVIO_ESPERA_MINUTOS` (5).
- Plantilla de correo `RECUPERACION_CLAVE` v1 con los marcadores obligatorios `nombre` y `enlace`.

## Reglas de seguridad

- Solo se guarda el SHA-256 del token; el token en claro nunca llega a la base de datos.
- La solicitud no revela si el correo existe: el SP devuelve 0 filas sin distinguir el motivo y no lanza.
- Un enlace sirve una sola vez, vence por parámetro y se revoca al pedir otro.
- Cualquier enlace que no sirve (inexistente, vencido, usado, revocado o de usuario inactivo) responde igual.
- El rol runtime solo tiene `EXECUTE` sobre los cuatro SP; no tiene permisos directos sobre la tabla.

## Archivos

| Archivo | Contenido |
|---|---|
| `schema/tables/TokenRecuperacionClave.sql`, `schema/tables/zz_foreign_keys.sql` | Tabla, índice y FK |
| `schema/stored-procedures/usp_*_recuperacion_clave.sql` | Los cuatro SP |
| `schema/seed/61_hu177_recuperacion_clave.sql` | Mensajes, parámetros y plantilla |
| `schema/security/rol_asistencias_runtime_hu177.sql` | Permisos |
| `migrations/35_hu177_recuperacion_clave_up.sql` y `_down.sql` | Migración |
| `test/test_hu177_recuperacion_clave.sql`, `test/test_hu177.ps1`, `test/test_hu177_migraciones.sql` | Pruebas |
| `test_suite.sql`, `test_summary.ps1`, `test/test_contract_closure.sql` | Registro de las pruebas y de los dos SP de lectura no canónicos |
| `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | Hash nuevo de `zz_foreign_keys.sql` (`scripts/freeze-manifest.ps1 -Mode UpdateCulm001D`), por la FK agregada |

No se modifica ningún objeto existente, salvo la FK que se agrega al final de `zz_foreign_keys.sql`.

## Despliegue y rollback

- La migración 35 va antes que el backend de HU177. Es idempotente.
- Rollback: `35_hu177_recuperacion_clave_down.sql`. Elimina los SP, la tabla y las semillas; los enlaces pendientes dejan de servir.

## Lo que no cubre la base de datos

- El envío real del correo depende del canal de notificaciones de cada ambiente.
- El aviso solo se entrega a usuarios con el correo confirmado (regla del canal de correo).
