---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-12
---

# PLAN — VAL-oleada1-urgentes (base de datos)

Origen: `informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`. Rama `fix/VAL-oleada1-urgentes`.

## ROL-05: retiro de POST /api/v1/usuarios

Decisión de John (2026-11-12). El backend retira `POST /api/v1/usuarios`: cualquier usuario autenticado creaba un usuario y su cuenta en el proveedor de identidad, sin ejecutor ni ámbito. Esa ruta era el único llamador de `dbo.usp_sincronizar_usuario` (CC-003G-01), y por eso el SP tampoco recibía ejecutor.

Quién lo llamaba, verificado antes de retirarlo:

| Llamador | Situación |
|---|---|
| Backend `UsuarioJpaRepository.crearUsuario` | Único llamador en código de aplicación; se retira con la ruta. |
| Otros SP, vistas o funciones de la BD | Ninguno: la prueba `VAL_ROL05_04` lo busca en `sys.sql_modules` y pasa en la BD local. |
| `test/test_usp_sincronizar_usuario.sql`, carreras de `test_summary.ps1`, `test/verify_runtime_role_cc003g01.ps1` | Pruebas del propio SP; se retiran o ajustan. |
| `test/fixtures/maint_003h_failsafe_data_fixture.sql` | Creaba un usuario de prueba con el SP público; pasa a `usp_sincronizar_usuario_interno` (corre como `sa`). |

`dbo.usp_sincronizar_usuario_interno` **no se toca**: es el núcleo de los altas con ámbito (`usp_crear_decano_interno`, `usp_crear_coordinador_interno`, `usp_vincular_docente_programa`, `usp_admitir_estudiante`, `usp_registrar_estudiante_en_grupo`, `usp_internal_matricular_por_token`) y sigue con `DENY EXECUTE` al runtime.

| Archivo | Cambio |
|---|---|
| `migrations/39_val_retiro_alta_usuarios_sin_ambito_up.sql` | `REVOKE EXECUTE` a `rol_asistencias_runtime` y `DROP PROCEDURE dbo.usp_sincronizar_usuario`; falla si falta el núcleo interno. Idempotente. Se numera 39 porque la 38 está en otra rama ya subida. |
| `migrations/39_val_retiro_alta_usuarios_sin_ambito_down.sql` | Recrea el SP y su `GRANT` tal como estaban. |
| `schema/stored-procedures/usp_sincronizar_usuario.sql` | Borrado (despliegue desde cero). La compuerta `PUBLIC_SP_INVENTORY` toma el inventario de esta carpeta. |
| `schema/security/rol_asistencias_runtime_cc003g01.sql` | Sin la comprobación de existencia ni el `GRANT` del SP retirado; conserva el del plan de estudio y los `DENY`. |
| `test/test_val_retiro_alta_usuarios_sin_ambito.sql` (nueva) | `VAL_ROL05_01..04` y `VAL_ROL05_TRANCOUNT_ZERO`. Registrada en `test_suite.sql` en lugar de `test_usp_sincronizar_usuario.sql`, que se borra. |
| `test_summary.ps1` | Fuera los identificadores `USER_SYNC_PUBLIC_*` y `CC003G01_CONCURRENT_USER_*` y las dos carreras de usuario; entran los `VAL_ROL05_*`. |
| `test/verify_runtime_role_cc003g01.ps1` | Comprueba que el SP ya no existe (`syncRetirado=1`) y prueba solo el proveedor de plan de estudio. |
| `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` | Líneas de la migración 39 (up y down) y de `rol_asistencias_runtime_cc003g01.sql`. |
| `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, `DOCUMENTACION_PROCEDIMIENTOS_ORQUESTADORES.md`, `especificacion_sp_endpoints.md` | El SP queda marcado como retirado. |

Fuera de alcance: `schema/security/rol_asistencias_runtime.sql` (hash congelado en el manifiesto UTC-D06) conserva un comentario histórico que nombra el SP; `docs/arquitectura/backend_specification.md` es una especificación antigua que cita el SP en operaciones que nunca se implementaron; los documentos de CC-003G-01 quedan como registro histórico.

## Validación

| Prueba | Resultado |
|---|---|
| `test/test_val_retiro_alta_usuarios_sin_ambito.sql` contra la BD local **sin** aplicar la migración 39 | `VAL_ROL05_01` y `VAL_ROL05_02` FALLAN como se espera (el SP y su permiso siguen); `VAL_ROL05_03`, `VAL_ROL05_04` y `VAL_ROL05_TRANCOUNT_ZERO` PASAN. Con la migración aplicada deben pasar las cinco. |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK` (culm001_d = 70). |
| Sintaxis de `test_summary.ps1` y `test/verify_runtime_role_cc003g01.ps1` | Sin errores de análisis de PowerShell. |
| Compuerta completa (`deploy_schema.ps1` + `test_summary.ps1`) | No ejecutada: la corre John. |

Pendiente fuera de la BD: retirar la ruta del PDP con `provision_asistencias.py` y `--prune` (aprobado por John).
