---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# TEST_PLAN — HU074: activar o inactivar asignaturas

Las pruebas salen de las reglas del [CONTRACT](CONTRACT.md). Los datos se insertan dentro de una transacción que se revierte al final.

## `test/test_hu074_estado_asignatura.sql` (registrada en `test_suite.sql`)

Datos de prueba: coordinador C con los programas P1 y P2, coordinador C2 con P3, docente D con vínculo activo en P1; un plan activo por programa; tres períodos de la institución (pasado, vigente y futuro, con meses de margen respecto de hoy). Asignaturas en el plan de P1: Libre (sin grupos), Vigente (grupo en el período vigente y otro en el pasado), Futuro (grupo en el futuro), Pasado (grupo solo en el pasado), Compartida (también en el plan de P3), Compartida propia (también en el plan de P2, con grupo vigente), Borde fin y Borde inicio (con grupo en dos períodos más: uno que termina hoy y otro que empieza mañana, con la fecha local institucional de `TIEMPO/ZONA_HORARIA_SQLSERVER`).

| ID | Conducta esperada |
|---|---|
| `HU074_01_INACTIVAR_SIN_GRUPOS` | Libre queda inactiva; `estadoResultado = 1`, `ASI_012` con el texto del catálogo |
| `HU074_02_REACTIVAR` | Libre vuelve a activa; `ASI_011` |
| `HU074_03_GRUPO_PERIODO_VIGENTE` | Vigente: `ASI_009`, `estadoResultado = 0`, sigue activa |
| `HU074_04_GRUPO_PERIODO_FUTURO` | Futuro: `ASI_009`, sigue activa |
| `HU074_05_GRUPO_SOLO_PERIODO_PASADO` | Pasado: se inactiva (`ASI_012`) |
| `HU074_06_COMPARTIDA_PROGRAMA_AJENO` | Compartida: `ASI_006`, sigue activa |
| `HU074_07_CREAR_GRUPO_INACTIVA` | `usp_crear_grupo` con Libre inactiva: `ASI_010`, no inserta el grupo |
| `HU074_08_ASOCIAR_PLAN_INACTIVA` | `usp_asociar_asignatura_plan` de Libre inactiva al plan de P2: `ASI_010`, no crea vínculo |
| `HU074_09_OFERTA_EXCLUYE_INACTIVA` | La oferta de creación de grupo de D no trae Libre y sí Vigente |
| `HU074_10_ASOCIABLES_EXCLUYE_INACTIVA` | Las asociables al plan de P2 no traen Libre y sí Vigente |
| `HU074_11_MALLA_MUESTRA_INACTIVA` | La malla del plan de P1 trae Libre con `estaActivaAsignatura = 0` y Vigente con 1 |
| `HU074_12_DESEADA_INACTIVA_YA_INACTIVA` | `@estaActivaDeseada = 0` sobre Pasado (ya inactiva): éxito `ASI_012`, sigue inactiva |
| `HU074_13_DESEADA_ACTIVA_YA_ACTIVA` | `@estaActivaDeseada = 1` sobre Vigente (activa, con grupos vigentes): éxito `ASI_011`, sin cambio y sin evaluar grupos |
| `HU074_14_DESEADA_ACTIVA_DESDE_INACTIVA` | `@estaActivaDeseada = 1` sobre Pasado inactiva: queda activa (`ASI_011`) |
| `HU074_15_COMPARTIDA_PROPIA_CON_GRUPO` | Compartida propia (planes de P1 y P2, ambos de C) con grupo vigente: `ASI_009`, no `ASI_006` |
| `HU074_16_BORDE_FIN_HOY` | Grupo en un período con `fechaFin` = hoy (fecha local institucional): vigente, `ASI_009` |
| `HU074_17_BORDE_INICIO_MANANA` | Grupo en un período con `fechaInicio` = mañana: futuro, `ASI_009` (pedido con `@estaActivaDeseada = 0`) |
| `HU074_18_CREAR_GRUPO_ACTIVA` | `usp_crear_grupo` con Vigente (activa) en el período futuro: `GEN_004`, inserta el grupo y no cierra la transacción del llamador (regresión de la transacción y el bloqueo) |
| `HU074_TRANCOUNT_ZERO` | No quedan transacciones abiertas |

## `test/test_hu074_migracion.sql` con `test/test_hu074_migracion.ps1` (registrada en `test_summary.ps1`)

| ID | Conducta esperada |
|---|---|
| `HU074_MIG_UP_DOWN_UP` | Dentro de una transacción revertida: el up sobre la base desplegada es idempotente; el down retira el interno y los mensajes y restaura los tres SP (el toggle vuelve a `GEN_004` y a su firma sin `@estaActivaDeseada`); el up dos veces los recrea (con `@estaActivaDeseada` y el bloqueo de fila en el toggle y en `usp_crear_grupo`) y conserva el `EXECUTE` del toggle |

## Pruebas existentes ajustadas

| Archivo | Cambio |
|---|---|
| `test/test_subject_catalog.sql` | `SUBJECT_TOGGLE` espera `ASI_012` al inactivar y `ASI_011` al reactivar (antes `GEN_004`) |

`test_rec2_rbac_asignatura.sql` y `test_culm001_b2nm_oferta_y_decano.sql` (que usan el toggle) no necesitan cambios: la primera solo verifica `estadoResultado` y el estado persistido (su asignatura no tiene grupos) y la segunda espera `ASI_006`, que se evalúa antes de la regla nueva.
