---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# PLAN — HU006-perfil-usuario: consulta del perfil propio

## Identidad y objetivo

- **Objetivo:** el usuario autenticado consulta su perfil (datos personales y vínculos institucionales por rol), leído de la DB.
- **Alcance aprobado por John (2026-10-27):** solo lectura. La edición del perfil (PUT) queda fuera.
- **Referencia:** el contrato HTTP y la validación de las 3 capas están en el work item homónimo del backend.

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `usp_consultar_perfil_usuario` | Nuevo (READ_QUERY_RESULTSET; una fila por vínculo; sin vínculos devuelve 1 fila con el vínculo en NULL; usuario inexistente devuelve 0 filas) |
| `schema/security/rol_asistencias_runtime_hu006.sql` | `GRANT EXECUTE` aditivo (THROW 52192 si falta el SP) |
| `test/test_usp_consultar_perfil_usuario.sql` | Nuevo (P-01..P-03), registrado en `test_suite.sql` |
| `test/test_contract_closure.sql` | Exclusión READ_QUERY_RESULTSET del SP |

## Reglas aplicadas (AGENTS.md)

- Sin cambios de tablas ni de objetos congelados.
- **Ámbito:** el SP solo lee el `@idUsuarioEjecutor` y no recibe otro id.
- **Contraseña:** el SP lee de `uv_usuario`, que la enmascara, y no la devuelve.
- **Mensajes:** solo `VAL_001`.

## Rollback

`DROP PROCEDURE` y `REVOKE`. No hay cambios de datos.
