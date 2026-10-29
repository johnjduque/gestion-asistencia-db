---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC3: endurecer las transacciones (XACT_ABORT / XACT_STATE)

## Hallazgo (auditoría BD 2026-10-28, severidad alta)

La regla de AGENTS.md exige `SET XACT_ABORT ON` en los SP que abren una transacción y revisar `XACT_STATE()` antes del ROLLBACK. La auditoría encontró 11 SP que abren transacción sin `XACT_ABORT ON`, y 4 de ellos hacen ROLLBACK sin revisar `XACT_STATE()`.

## Análisis por SP

| SP | Congelado | Patrón actual | Decisión |
|---|---|---|---|
| `usp_ejecutar_cierre_masivo_periodo` | No | `BEGIN TRAN` propio. El CATCH hace `IF @@TRANCOUNT > 0 ROLLBACK` | **Corregido** |
| `usp_radicar_solicitud_revision_asistencia` | No | Igual | **Corregido** |
| `usp_resolver_solicitud_revision_asistencia` | No | Igual | **Corregido** |
| `usp_crear_decano` | No | Transacción propia o `SAVE TRANSACTION` si hay una del llamador; revisa `XACT_STATE()` en todos los caminos | **No se toca** (falso positivo) |
| `usp_crear_coordinador` | No | Igual | **No se toca** (falso positivo) |
| `usp_registrar_o_actualizar_plan_estudio` | No | Igual | **No se toca** (falso positivo) |
| `usp_sincronizar_usuario` | No | Igual | **No se toca** (falso positivo) |
| `usp_generar_sesiones_grupo` | **Sí** (DEVELOP_FREEZE y UTC_D06) | El mismo defecto que los 3 corregidos | Propuesta, pendiente de aprobación |
| `usp_registrar_asistencias_sesion` | **Sí** (DEVELOP_FREEZE, Golden Path) | Savepoint y `XACT_STATE()` correctos | Propuesta, pendiente de aprobación |
| `usp_clasificar_procedencia_sesion` | **Sí** (UTC_D06) | Savepoint y `XACT_STATE()` correctos | Propuesta, pendiente de aprobación |
| `usp_crear_sesion_interno` | **Sí** (UTC_D06) | Savepoint y `XACT_STATE()` correctos | Propuesta, pendiente de aprobación |

### Por qué los 4 SP con savepoint NO llevan `XACT_ABORT ON`

Primero se probó agregarlo y el gate falló: `USER_SYNC_PUBLIC_ROLLBACK_SAVEPOINT` dio `Msg 3930`, y se cayeron las pruebas `*_ROLLBACK_SAVEPOINT` del plan de estudio.

**Contrato que cumplen hoy:** si el llamador ya tiene una transacción y el SP falla, revierte **solo hasta su savepoint** y la transacción del llamador sigue viva.

**Qué rompe `XACT_ABORT ON`:**
- condena la transacción completa ante cualquier error (`XACT_STATE() = -1`);
- el savepoint ya no sirve y el SP tiene que propagar el error;
- se pierde el contrato anterior.

**Conclusión:**
- En estos SP la ausencia de `XACT_ABORT` es **intencional**.
- Su manejo de `XACT_STATE()` ya es correcto.
- La regla T1 de la auditoría queda como **falso positivo** para el patrón "transacción propia o savepoint".

### Qué se corrigió en los 3 SP

- `SET XACT_ABORT ON` después de `SET NOCOUNT ON`. Ante un error, o una cancelación o timeout del cliente (cuando el CATCH no llega a ejecutarse), SQL Server revierte toda la transacción y no queda abierta con bloqueos.
- En el CATCH, `IF @@TRANCOUNT > 0 ROLLBACK` pasa a `IF XACT_STATE() <> 0 ROLLBACK`. Solo se revierte si hay una transacción viva, lo que evita un segundo error que tape el original.
- **Límite conocido:** estos 3 SP no usan el patrón de savepoint. Si se invocan dentro de la transacción de un llamador y fallan, revierten también la del llamador, igual que antes. El backend los invoca sin transacción externa. Pasarlos al patrón de savepoint queda como mejora futura opcional.

## Pruebas

`test/test_rec3_falla_intermedia_transaccion.sql`:
- Las fixtures se confirman y se limpian siempre, porque el SP debe ser dueño de su transacción.
- **Precondición:** la misma llamada, sin la falla y dentro de una transacción que se revierte, debe ser exitosa.
- **Inyección de la falla:** un CHECK temporal (`WITH NOCHECK`, limitado a las filas de la prueba) sobre la tabla de la **segunda** escritura.
- Las llamadas usan `EXEC` directo, porque SQL Server no permite ROLLBACK dentro de `INSERT-EXEC`.

| ID | SP | 1.ª escritura (debe revertirse) | 2.ª escritura (falla) |
|---|---|---|---|
| TX-01 | Radicar revisión | `Asistencia` | `SolicitudRevisionAsistencia` |
| TX-02 | Resolver revisión | `SolicitudRevisionAsistencia` (estado y respuesta) | `DetalleAsistencia.asistio` |
| TX-03 | Cierre masivo | `EstudianteGrupo` → F | Contadores de `Grupo` |

Cada caso verifica:
- que la 1.ª escritura se revirtió;
- que la 2.ª no persistió;
- que `@@TRANCOUNT = 0`;
- y, al final de la prueba, que no queden restricciones temporales.

Las pruebas son de **regresión**: con el código anterior también pasaban cuando el SP era dueño de la transacción. El beneficio propio de `XACT_ABORT ON` (cancelación o timeout del cliente) no se puede simular desde sqlcmd.

## Propuesta para los 4 congelados (requiere aprobación explícita de John y work item post-freeze)

1. **`usp_generar_sesiones_grupo`:**
   - el mismo cambio de 2 líneas que los 3 corregidos (`SET XACT_ABORT ON` y `IF XACT_STATE() <> 0 ROLLBACK`);
   - prueba TX con falla en la inserción de `Sesion`;
   - regenerar su hash con `freeze-manifest -Mode GeneratePostFreeze`.
2. **`usp_registrar_asistencias_sesion`, `usp_clasificar_procedencia_sesion` y `usp_crear_sesion_interno`:**
   - ya tienen el patrón de savepoint y revisan bien `XACT_STATE()`;
   - **no se recomienda** agregar `XACT_ABORT ON`, por la misma razón que los 4 de arriba.
   - Recomendación: no tocarlos.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29), con `origin/develop` integrado (#60):
- `TOTAL_EXECUTED=381`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`;
- `TEST_PASS:REC3_TX01..TX03`;
- regresión verde: `MASS_CLOSE_SUCCESS`, `REVIEW_*`, `*_ROLLBACK_SAVEPOINT`;
- `freeze-manifest -Mode Verify` OK: no se modificó ningún objeto congelado.

## Rollback

Revertir el commit. Solo cambian dos líneas por SP, en 3 SP, y se agrega una prueba.
