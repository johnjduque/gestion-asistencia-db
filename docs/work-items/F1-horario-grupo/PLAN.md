---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-31
---

# PLAN — F1: guardar el horario semanal del grupo

## Decisión

John (2026-10-30), dentro del plan de sesiones y faltas (`informes/PLAN_SESIONES_FALTAS_2026-10-30.md`, fuera del repo):
- El **coordinador define el horario** del grupo. El docente solo lo consulta, y sus cambios irán por la aprobación de sesiones (F6).
- Un grupo puede tener **varias franjas**, en días distintos o en el mismo día, **sin traslapes entre ellas**.
- **Al cambiar el horario se regeneran las sesiones futuras** (las que no han empezado y no tienen asistencia), pero eso es de **F2 (precarga)**. F1 solo guarda el horario.

## Hallazgo que motiva F1

- Hasta ahora `dbo.Horario` solo se llenaba desde los seeds: ningún SP ni endpoint la escribía.
- El backend respondía 501 si el cuerpo de crear o actualizar grupo traía horario.
- Sin horario guardado no hay precarga de sesiones ni sirve la validación de cruce del docente (#70).

## Cambios en la BD

1. **SP nuevo `usp_guardar_horarios_grupo`** (público, COORDINADOR del programa del grupo):
   - reemplaza todas las franjas del grupo;
   - valida formato (`HOR_004`), franjas cruzadas (`HOR_003`) y cruce del docente (`HOR_002`);
   - usa transacción propia, o savepoint si ya hay una transacción abierta;
   - un rechazo no deja escrituras parciales.
2. **Mensajes nuevos** `HOR_003` y `HOR_004` en `schema/seed/04_mensaje.sql` (usuario y técnico). `docs/catalogos/catalogo-mensajes.md` se regenera.
3. **Vistas, cambios aditivos y no congelados:**
   - `uv_dia` expone `codigo`;
   - `uv_horario` expone `codigoDia`.
4. **Permiso:** `schema/security/rol_asistencias_runtime_f1_horario_grupo.sql` (archivo nuevo) da `GRANT EXECUTE` sobre el SP y `DENY INSERT, UPDATE, DELETE` sobre `dbo.Horario`. `rol_asistencias_runtime.sql`, que está congelado, no se toca.

**Qué NO cambia:**
- `usp_crear_grupo` y `usp_actualizar_grupo` (de Sergio): el backend invoca el SP nuevo después de ellos, en la misma transacción.
- Los objetos congelados.
- Las tablas: no se crean ni se modifican.

## Matriz de pruebas (`test/test_usp_guardar_horarios_grupo.sql`)

| ID | Escenario | Esperado |
|---|---|---|
| `GROUP_SCHEDULE_SAVE_SUCCESS` | Dos franjas en días distintos | Se guardan 2 franjas |
| `GROUP_SCHEDULE_REPLACE` | Guardar otra vez con una franja distinta | Queda solo la nueva |
| `GROUP_SCHEDULE_OVERLAP_REJECTED` | Lunes 08-10 y lunes 09-11 en el mismo grupo | `HOR_003` con las dos franjas; el horario anterior no cambia |
| `GROUP_SCHEDULE_ADJACENT_ALLOWED` | Lunes 08-10 y lunes 10-12 (con el código en minúsculas) | Se guardan |
| `GROUP_SCHEDULE_INVALID` | Arreglo vacío, objeto, día inexistente, fin <= inicio, hora mal formada, clave extra | `HOR_004` con el motivo; sin cambios |
| `GROUP_SCHEDULE_TEACHER_CONFLICT_SAVEPOINT` | El docente ya tiene otro grupo el martes 08-10 (con transacción externa) | `HOR_002`; rollback al savepoint, sin franjas parciales; la transacción externa se conserva |
| `GROUP_SCHEDULE_TEACHER_CONFLICT_OWN_TRANSACTION` | El mismo cruce sin transacción externa | `HOR_002`; rollback propio; sin transacción abierta |
| `GROUP_SCHEDULE_SCOPE` | Coordinador de otro programa y ejecutor docente | `SEC_002` y `SEC_001`; sin cambios |

## Backend y frontend (ramas `feature/F1-horario-grupo`)

- **Backend:**
  - `POST` y `PUT /api/v1/grupos` aceptan `franjas` (el formato anterior `dias` + horas sigue funcionando) y guardan el horario en la misma transacción;
  - `GET /api/v1/grupos` devuelve las franjas;
  - `HOR_003` y `HOR_004` responden 400;
  - no hay rutas nuevas.
- **Frontend:**
  - pantalla nueva del coordinador `/app/coordinador/grupos` (crear y editar grupo con su horario);
  - el docente ya no crea ni edita grupos: esos endpoints solo los admiten COORDINADOR y ADMINISTRADOR.

## Siguiente (F2)

`usp_generar_sesiones_grupo` (congelado) solo lo ejecuta el docente titular y genera desde el inicio del período. La precarga desde el coordinador y la regeneración de solo las sesiones futuras necesitan una de dos cosas: aprobación para tocar ese SP congelado (John y José Alejandro) o un generador nuevo.

## Validación

Ver `VALIDATION.md`.
