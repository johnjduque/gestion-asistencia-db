# DEDUP — validaciones compartidas de sesión

## Motivo

El análisis de SonarCloud de `develop` falla desde el 2026-11-10 por código duplicado: 1587 líneas duplicadas sobre 48425 de código nuevo (3,28 %), con un límite de 3 %. Las pruebas de BD pasan; lo que falla es el umbral de duplicación.

John pidió quitar la duplicación real en los procedimientos, sin tocar la configuración de SonarCloud (2026-11-10).

## Alcance

Dos bloques de validación estaban copiados en procedimientos de sesiones:

| Bloque repetido | Dónde estaba | Qué queda |
|---|---|---|
| Correlación, ejecutor, RBAC `COORDINADOR`, sesión existente y ámbito del coordinador sobre el grupo | `usp_cancelar_sesion_coordinador` y `usp_validar_coordinador_sesion_interno` | `usp_cancelar_sesion_coordinador` llama a `usp_validar_coordinador_sesion_interno` |
| Correlación, ejecutor y sesión obligatorios, RBAC `DOCENTE` y titularidad `SESION` | `usp_consultar_destinatarios_sesion_cancelada` y `usp_consultar_destinatarios_sesion_manual` | Los dos llaman al interno nuevo `usp_validar_docente_titular_sesion_interno` |

Son unas 228 líneas duplicadas menos (58 + 58 y 56 + 56 según SonarCloud).

## Lo que no cambia

- Firmas, columnas, orden de columnas, mensajes, códigos de catálogo y permisos de los tres procedimientos públicos.
- El interno nuevo no se concede a `rol_asistencias_runtime`: se usa por encadenamiento de propiedad, igual que `usp_validar_coordinador_sesion_interno`.
- Ningún objeto congelado ni la configuración de SonarCloud.

## Diferencia de comportamiento conocida

`usp_cancelar_sesion_coordinador` validaba dentro de su propio `TRY`. Ahora la validación corre dentro del `TRY` de `usp_validar_coordinador_sesion_interno`, que ante un error inesperado responde `SYS_001` con `estadoResultado = 0`, igual que antes. La única diferencia es que, si el error ocurre con una transacción externa ya condenada, antes se propagaba con `THROW` desde la validación y ahora se responde `SYS_001`. Es el mismo comportamiento que ya tienen `usp_aprobar_solicitud_sesion` y `usp_rechazar_solicitud_sesion`.

## Archivos

| Archivo | Cambio |
|---|---|
| `schema/stored-procedures/usp_validar_docente_titular_sesion_interno.sql` | Nuevo |
| `schema/stored-procedures/usp_consultar_destinatarios_sesion_cancelada.sql` | Delegan la validación |
| `schema/stored-procedures/usp_consultar_destinatarios_sesion_manual.sql` | Delegan la validación |
| `schema/stored-procedures/usp_cancelar_sesion_coordinador.sql` | Delegan la validación |
| `migrations/34_deduplicar_validaciones_sesion_up.sql` y `_down.sql` | El `up` crea el interno y actualiza los tres procedimientos; el `down` restaura los textos previos y elimina el interno |
| `test/test_dedup_validaciones_sesion.ps1` y `test/test_dedup_validaciones_sesion_migraciones.sql` | Migración 34 up → down → up |
| `test_summary.ps1` | Registra `DVS_MIG_UP_DOWN_UP` |
| `docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md`, `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` | Documentación |

## Despliegue y rollback

- La migración 34 va después de la 33. No toca datos y es idempotente.
- El backend no cambia: los contratos de los tres procedimientos son los mismos.
- Rollback: `34_deduplicar_validaciones_sesion_down.sql`.

## Pendiente

- Confirmar el porcentaje en SonarCloud cuando analice `develop` después de unir el PR. La estimación es cerca de 2,8 %.
- Quedan otros pares duplicados que no se tocaron (por ejemplo, las consultas de solicitudes de revisión del estudiante y del docente). Si el margen resulta corto, son los siguientes candidatos.
