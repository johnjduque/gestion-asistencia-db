# HU177 — recuperar contraseña: retiro del flujo propio

## Decisión

John, 2026-11-11: recuperar la contraseña **no es de esta aplicación**. Es del servicio de seguridad de terceros (Security Baseline / Keycloak), y la aplicación debe apoyarse en él. HU177 queda **pendiente de terceros**.

Esta decisión reemplaza la del mismo día que aprobó un flujo propio (enlace de un solo uso por correo). Ese flujo se implementó, se probó y estuvo unas horas en `develop` (PR #121 de BD, migración 35). Se retira completo.

## Qué se retira de la base de datos

| Objeto | Estado |
|---|---|
| Tabla `TokenRecuperacionClave` y su FK en `zz_foreign_keys.sql` | Retirada |
| `usp_consultar_solicitud_recuperacion_clave`, `usp_emitir_token_recuperacion_clave`, `usp_consultar_token_recuperacion_clave`, `usp_consumir_token_recuperacion_clave` | Retirados |
| Mensajes `RCL_001`…`RCL_003`, parámetros `RECUPERACION_CLAVE/*`, plantilla de correo `RECUPERACION_CLAVE` | Retirados |
| `rol_asistencias_runtime_hu177.sql`, migración `35_hu177_recuperacion_clave_up|down.sql` y sus pruebas | Retirados del repositorio |
| Hash de `zz_foreign_keys.sql` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | Vuelve al valor anterior |

El repositorio queda como estaba antes de HU177, más la migración de limpieza.

## Migración 36

`36_hu177_retiro_recuperacion_clave_up.sql` elimina esos objetos y semillas **solo si existen**. Sirve para los ambientes donde se alcanzó a aplicar la 35; donde no se aplicó no hace nada. Es idempotente. Su `down` no tiene efecto: el flujo ya no existe en el repositorio y no se recrea.

El número 35 queda sin usar a propósito, para que nadie lo reutilice con otro contenido.

## Qué queda para HU177

- En esta aplicación: el botón "¿Olvidaste tu contraseña?" del login, que por ahora informa que la recuperación no está habilitada.
- En el servicio de seguridad de terceros: activar la recuperación de contraseña y su correo. Cuando exista, el botón se conecta con ella.

## Pruebas

`test/test_hu177_retiro.ps1` (`HU177_RETIRO_MIG`): simula los restos de la migración 35, aplica la 36 y comprueba que no queda nada; la repite y aplica el `down` sin que se recree nada.
