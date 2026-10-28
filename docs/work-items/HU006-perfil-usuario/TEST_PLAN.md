---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# TEST_PLAN — HU006-perfil-usuario

La matriz completa está en el `TEST_PLAN.md` del work item homónimo del backend. Estos son los casos de base de datos, que corren dentro de una transacción con ROLLBACK:

| ID | Escenario | Esperado |
|---|---|---|
| P-01 | U1 con los 5 roles | 6 vínculos, en este orden: estudiante (P1), docente en P1 (activo) y en P2 (inactivo), coordinador (P2), decano (F) y administrador (institución). Datos personales correctos y detalle por rol (facultad o tipo de vinculación) |
| P-02 | U2 sin vínculos | 1 fila con el vínculo en NULL; no aparece ningún dato de otro usuario |
| P-03 | Id inexistente / ejecutor nulo | 0 filas / `VAL_001` |

**RED:** falla por objeto inexistente hasta que se crea el SP.
