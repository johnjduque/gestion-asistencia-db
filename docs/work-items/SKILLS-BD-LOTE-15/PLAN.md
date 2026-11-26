---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 15: cobertura y documentación pendientes

## Contexto

La re-auditoría de la rama larga `refactor/skills-bd` después de los lotes 0-14
(`informes/AUDITORIA_BD_SKILLS_2026-11-26_rama_skills-bd.md`) dejó cuatro pendientes menores. Este lote los cierra sobre la misma
rama. Regla del lote: **no cambia ningún objeto de la BD** (solo pruebas y documentación).

## Cambios

| Pendiente | Qué se hizo |
|---|---|
| `IS NULL OR` en `uv_auth_decano` | Se deja como está (decisión de John, 2026-11-26): la institución del decano sale de su facultad y la HU178 crea decanos sin facultad, que el administrador debe ver para asignarles una. Documentado como excepción E9 en `docs/arquitectura/excepciones-skills-bd.md` |
| 29 vistas finas nuevas (lotes 5-14) sin prueba propia | `test/test_skills_lote15_cobertura.sql`: columnas exactas y en orden (`SKL15_V01`), mismas filas que la tabla base (`SKL15_V02`) y ninguna columna de hash de token, PIN ni contraseña (`SKL15_V03`) |
| `usp_actualizar_nombres_usuario_interno` y `usp_registrar_auditoria_identidad_interno` sin prueba directa | Misma prueba: `SKL15_I01` (solo cambian los nombres que llegan; usuario inexistente no escribe), `SKL15_I02` (evento con motivo recortado, identidad anterior y nueva; motivo en blanco queda NULL) y `SKL15_I03` (identidad anterior que no es JSON: relanza el error 13609 con la transacción del llamador condenada y no deja el evento) |
| 14 SP públicos sin ficha | Addendum "SKILLS-BD lote 15" en `docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` |

La prueba está registrada en `test_suite.sql` (después del lote 14) y sus 6 ids en `test_summary.ps1`.

## Verificación

- La prueba nueva pasa sobre el esquema de la rama.
- Gate local completo (`deploy_schema.ps1`, `migrar.ps1`, `test_summary.ps1`): ver el commit del lote.
