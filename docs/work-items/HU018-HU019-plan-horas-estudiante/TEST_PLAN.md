---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-10
---

# TEST_PLAN — HU018-HU019: plan de estudios y horas programadas del estudiante

Las pruebas salen de las reglas del [PLAN](PLAN.md). Los datos de prueba se insertan dentro de una transacción que se revierte al final.

## `test/test_hu018_hu019_plan_horas_estudiante.sql` (registrada en `test_suite.sql`)

Datos de prueba: dos programas (P1 y P2) de una facultad; el estudiante E1 en P1 y E2 en P2. P1 tiene un plan activo con los semestres 1, 2 y 3 y un plan inactivo. En el plan activo: semestre 1 con una obligatoria y una optativa, semestre 2 con una asignatura activa, una inactiva y un vínculo desvinculado, y semestre 3 vacío. E1 está inscrito en los grupos de dos asignaturas y retirado del grupo de otra. Un grupo tiene tres sesiones de 2 horas y una cuarta cancelada.

| ID | Conducta esperada |
|---|---|
| `HU018_PLAN_ESTRUCTURA_ORDEN` | E1 recibe 4 filas: las dos asignaturas del semestre 1 (primero la obligatoria, aunque su nombre va después en el alfabeto), la del semestre 2 y el semestre 3 en una fila sin asignatura. Datos del programa, plan, semestre, créditos, carácter y componente correctos |
| `HU018_PLAN_EXCLUSIONES` | No aparecen el plan inactivo, el plan del otro programa, la asignatura inactiva ni el vínculo desvinculado |
| `HU018_PLAN_CURSANDO` | `cursando = 1`, con su grupo, solo donde la matrícula está inscrita; la matrícula retirada no cuenta |
| `HU018_PLAN_PRIVACIDAD` | E2 ve solo el plan de su programa; un docente obtiene 0 filas; el ejecutor nulo responde `VAL_001` |
| `HU018_PLAN_COLUMNAS` | El resultset tiene las 18 columnas del contrato, con su nombre y en su orden |
| `HU019_HORAS_PROGRAMADAS` | El grupo con tres sesiones y una cancelada devuelve 3 sesiones y 6 horas; el grupo sin sesiones devuelve 0 y 0; la matrícula retirada no aparece; solo salen matrículas del propio estudiante; las horas dictadas del resumen no superan las programadas |
| `HU019_HORAS_VALIDACIONES` | Un docente obtiene 0 filas; el ejecutor nulo responde `VAL_001`; el resultset tiene las 4 columnas del contrato |

## `test/test_hu018_hu019_migraciones.sql` con `test/test_hu018_hu019.ps1` (registrada en `test_summary.ps1`)

| ID | Conducta esperada |
|---|---|
| `HU018_HU019_MIG_UP_DOWN_UP` | El `down` elimina los dos SP y no toca objetos existentes; el `up` los crea con `EXECUTE` para el rol runtime; repetir el `up` no cambia los textos; `down` y `up` reproducen el primer `up`; la transacción se revierte |

## `test/test_public_objects.sql`

| ID | Conducta esperada |
|---|---|
| `HU018_HU019_SEG_01` | Los dos SP tienen `EXECUTE` para `rol_asistencias_runtime` |

## `test/test_contract_closure.sql`

Los dos SP se agregan a las listas de SP de lectura con resultset de datos (no el canónico de 4 columnas). `PUBLIC_CANONICAL_RESULTSET` debe seguir pasando.
