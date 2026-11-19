---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# CONTRACT — HU074: activar o inactivar asignaturas

Ningún resultset cambia y ninguna firma pierde ni reordena parámetros (no breaking); la única extensión es aditiva: `@estaActivaDeseada BIT = NULL` al final de `usp_toggle_estado_asignatura`. Todos los SP públicos devuelven la tupla canónica
`idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado`; el mensaje técnico lleva
`DBCODE=<código>|<texto técnico> Correlacion: <idCorrelacion>`.

## Mensajes nuevos (`schema/seed/70_hu074_mensajes_estado_asignatura.sql`)

| Código | Tipo | Severidad | Mensaje de usuario |
|---|---|---|---|
| `ASI_009` | BUSINESS_ERROR | ALTO | No puedes inactivar la asignatura: tiene grupos en el período vigente o en períodos futuros. |
| `ASI_010` | BUSINESS_ERROR | MEDIO | La asignatura está inactiva; actívala para usarla. |
| `ASI_011` | SUCCESS | BAJO | La asignatura quedó activa. |
| `ASI_012` | SUCCESS | BAJO | La asignatura quedó inactiva. |

## `dbo.usp_toggle_estado_asignatura(@idAsignatura, @idCorrelacion, @idUsuarioEjecutor = NULL, @estaActivaDeseada BIT = NULL)`

Orden de validación:

1. Correlación presente.
2. `usp_validar_gestion_asignatura_coordinador_interno` con `@exigirTodosLosProgramas = 1`: `GEN_002` (sin ejecutor), `SEC_001` (no es COORDINADOR), `VAL_002` (asignatura inexistente), `SEC_002` (no coordina ningún programa con vínculo activo), `ASI_006` (compartida con programas que no coordina).
3. Abre transacción (si el llamador no tiene una; `SET XACT_ABORT ON`) y lee `dbo.Asignatura.estado` con `UPDLOCK, HOLDLOCK`. Estado pedido = `@estaActivaDeseada` o, si es `NULL`, el contrario del leído.
4. Si el estado pedido es el actual: éxito sin cambios, `ASI_011` (activa) o `ASI_012` (inactiva); no evalúa la regla de grupos.
5. Si se pide inactivar una activa y existe un grupo de la asignatura con `uv_periodo_academico.estado <> 'CERRADO'` (vigente o futuro, cualquier programa; `fechaFin = hoy` cuenta como vigente y `fechaInicio = mañana` como futuro, con la fecha local institucional): `ASI_009`, `estadoResultado = 0`, sin cambios.
6. Si no: fija `Asignatura.estado` al estado pedido en la misma transacción. Éxito `ASI_012` (1 → 0) o `ASI_011` (0 → 1), `estadoResultado = 1`.

Error inesperado: `SYS_001`.

## `dbo.usp_crear_grupo`

Después de validar la existencia de la asignatura (`VAL_002`), y antes de resolver el período: asignatura inactiva → `ASI_010`, `estadoResultado = 0`, sin `INSERT`. Desde esa validación hasta el `INSERT` corre en una transacción (la propia, o la del llamador si ya hay una; `SET XACT_ABORT ON`) con la fila de la asignatura leída con `UPDLOCK, HOLDLOCK` (mismo bloqueo que el toggle). Mensajes, orden de validaciones y resultset sin cambio.

## `dbo.usp_asociar_asignatura_plan`

- Asignatura inexistente o sin vínculos en la institución del plan → `GEN_001` (sin cambio).
- Asignatura inactiva → `ASI_010` (antes también `GEN_001`). Se valida antes de abrir la transacción y del interno de vínculo.

## `dbo.usp_validar_asignatura_activa_interno(@idAsignatura, @idCorrelacion, @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado OUTPUT, @estadoResultado OUTPUT, @bloquearFila BIT = 0)`

Interno, sin `EXECUTE` para `rol_asistencias_runtime`. `ASI_010` si la asignatura existe y está inactiva; en otro caso `estadoResultado = 1` con mensajes vacíos. Con `@bloquearFila = 1` lee `dbo.Asignatura` con `UPDLOCK, HOLDLOCK` (el llamador debe tener una transacción abierta); con `0` lee `uv_asignatura`.

## Consultas (sin cambio)

- `usp_consultar_oferta_creacion_grupo_docente` y `usp_consultar_asignaturas_asociables_paginado` excluyen las asignaturas inactivas.
- `usp_consultar_asignaturas_plan_paginado` (malla) las incluye con `estaActivaAsignatura = 0`.

## Backend

Detección por código: `DbTechnicalError.parse` lee el `DBCODE=` del mensaje técnico y `DbFailureClassifier.classifyDbCode` lo traduce. `ASI_009` y `ASI_010` ya se clasifican como `CONFLICT` (409) con su propio code, como `ASI_005`/`ASI_006`. Los éxitos `ASI_011`/`ASI_012` no requieren clasificación. `@estaActivaDeseada` es opcional: sin él el SP alterna como antes.
