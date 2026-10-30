---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-30
---

# PLAN — Eliminar `usp_validar_grupo_exista_para_docente_interno`

## Decisión

John (2026-10-30): eliminar `usp_validar_grupo_exista_para_docente_interno`. Se había conservado solo porque lo invocaba `usp_validar_cruce_horario_docente_interno`. En el work item `BD-cruce-horario-docente` (#70) esa invocación se quitó: el interno exigía que el grupo estuviera en el período vigente, y eso impedía cambiar el titular de grupos de otro semestre. Desde entonces el SP no tiene callers.

## Evidencia de que no tiene uso

- **BD:** ningún SP, vista, función, trigger, seed, prueba ni archivo de `schema/security` lo nombra. Solo aparecía en su propio archivo y en `migrations/08_eliminar_codigo_sin_uso_down.sql`.
- **Backend, frontend e Infra:** ninguna referencia.
- **Congelamiento:** no figura en ningún manifiesto de `docs/contracts/*.sha256`.
- **Rollback de la migración 08:** su `_down` restaura `usp_registrar_docente_en_grupo_interno`, que invocaba este SP. Si alguna vez se ejecuta ese `_down`, hay que ejecutar antes el `_down` de la 09.

## Cambios

1. **Schema:** se borra `schema/stored-procedures/usp_validar_grupo_exista_para_docente_interno.sql`.
2. **Migración:**
   - `migrations/09_eliminar_validar_grupo_docente_up.sql` hace `DROP PROCEDURE IF EXISTS`; es idempotente;
   - `_down.sql` restaura la definición de `develop` (`950877d`).
3. **Documentación:**
   - ficha 15 de `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` marcada como ELIMINADO;
   - en `especificacion_sp_endpoints.md`, las transacciones 2.1, 2.2 y 2.3 ahora nombran los validadores vigentes (`usp_validar_grupo_exista_por_id_interno` y `usp_validar_titularidad_jerarquica_interno`), y se quita la fila del índice de internos;
   - `transaccion-procedimiento.md`: entrada marcada como eliminada e inventario actualizado a 146 SP (89 públicos y 57 internos).
4. **Corrección de documentación de #69:** las notas "ELIMINADO (2026-10-29)" se habían publicado con `&` en lugar de comillas invertidas y barras (`&schema&&`). Se corrigen en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS/ORQUESTADORES/PUBLICOS.md` y `transaccion-procedimiento.md`.

Ninguna prueba nombraba este SP, así que no se quitan suites ni IDs requeridos.

## Validación

Ver `VALIDATION.md`.
