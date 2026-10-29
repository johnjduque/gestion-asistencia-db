---
status: active
type: work-item
scope: db+backend
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC2: ejecutor y RBAC en `usp_actualizar_asignatura` y `usp_toggle_estado_asignatura`

## Hallazgo

Auditoría de la BD contra los skills (2026-10-28), severidad alta:

- Los dos SP públicos no recibían `@idUsuarioEjecutor` ni validaban rol o ámbito.
- Ambos tienen `GRANT EXECUTE` al runtime y el backend los invoca.
- A nivel de BD, cualquier llamada con el rol runtime podía editar o desactivar cualquier asignatura. Esto incumplía:
  - el contrato base ("los SP públicos protegidos requieren ejecutor", `GEN_002`);
  - el skill `modelo-jerarquico-rbac`.

El backend ya validaba en el caso de uso que la asignatura fuera del programa del coordinador. La BD era la capa que faltaba.

## Decisión

**Quién puede:** el **COORDINADOR titular del programa** al que pertenece la asignatura (por la cadena Asignatura → SemestrePlanEstudio → PlanEstudio → Programa). El administrador queda fuera, según el modelo jerárquico.

**Ampliación futura al decano:** basta con cambiar `@codigoPerfilRequerido` a `'COORDINADOR,DECANO'` y validar la titularidad de `FACULTAD` cuando el perfil sea decano. Está anotado en el PASO 1.2 de cada SP.

**Expand & Contract y por qué el ejecutor es obligatorio desde ya:**
- La prueba de contrato `PUBLIC_SECURITY_EXECUTOR_REQUIRED` (`test_contract_closure.sql`) **prohíbe** el patrón `@idUsuarioEjecutor IS NOT NULL`, que sería necesario para un ejecutor opcional. Por eso se usa el patrón vigente del repo, el mismo de `usp_crear_asignatura` y `usp_cambiar_estado_plan_estudio`:
  - el parámetro va al final con `= NULL`, así las llamadas antiguas siguen compilando;
  - si llega NULL se responde `GEN_002`, sin escribir nada (fail-closed).
- La "fase 2" (volverlo obligatorio) queda absorbida en este cambio. Lo único pendiente de fases es el **orden de despliegue**:
  1. desplegar la BD;
  2. desplegar **en el mismo merge** el backend, que ya envía el ejecutor.
  - Entre los dos pasos, editar o cambiar el estado de una asignatura responde `GEN_002`. Falla cerrado y no corrompe datos.

## Cambio

**BD:**
- `usp_actualizar_asignatura` y `usp_toggle_estado_asignatura`:
  - nuevo `@idUsuarioEjecutor UNIQUEIDENTIFIER = NULL`;
  - PASO 1.1 `GEN_002`;
  - PASO 1.2 RBAC `COORDINADOR` (`SEC_001`);
  - PASO 2.1 titularidad `PROGRAMA` con `usp_validar_titularidad_jerarquica_interno` (`SEC_002`).
- Lecturas por las vistas `uv_asignatura` y `uv_semestre_plan_estudio`.

**Backend** (rama `fix/REC2-rbac-asignatura`):
- `AsignaturaCommandPort.actualizarAsignatura(..., usuarioEjecutor)` y `toggleEstadoAsignatura(id, usuarioEjecutor)`.
- `AsignaturaJpaRepository` envía `@idUsuarioEjecutor`.
- `GestionarAsignaturaUseCaseImpl` pasa el ejecutor que ya tenía.

**Pruebas:**
- `test/test_rec2_rbac_asignatura.sql`, con fixtures propias y ROLLBACK:

| ID | Caso | Esperado |
|---|---|---|
| RA-01 | Sin ejecutor (actualizar y toggle) | `GEN_002`, sin cambios |
| RA-02 | Ejecutor DOCENTE | `SEC_001`, sin cambios |
| RA-03 | Coordinador de otro programa | `SEC_002`, sin cambios |
| RA-04 | Coordinador titular | Éxito en ambos |

- `test/test_subject_catalog.sql`: el fixture ahora elige un plan y **su** coordinador, y envía el ejecutor.

**Documentación:**
- `especificacion_sp_endpoints.md`
- `transaccion-procedimiento.md` (SP-001 y SP-035)
- `reportes/reporte_auditoria_roles_permisos_jerarquia_develop.md`

## Nota para Alejo (PDP / Security Baseline)

- La regla nueva coincide con lo que el backend ya aplicaba en `GestionarAsignaturaUseCaseImpl`: coordinador del programa de la asignatura. No cambia la política del PEP/PDP. Agrega la defensa en profundidad en la BD.
- El `ForbiddenException` del backend sigue siendo la primera barrera. `SEC_001`/`SEC_002` de la BD solo aparecerían si el backend se saltara esa validación.

## Validación

- **BD**, réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29):
  - `TOTAL_EXECUTED=368`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`;
  - `TEST_PASS:REC2_RA01..RA04` y `SUBJECT_*` (5) en verde;
  - la prueba de contrato `PUBLIC_SECURITY_EXECUTOR_REQUIRED` sigue pasando.
  - re-ejecutada tras integrar `origin/develop` (#60, pruebas de coordinador e identidad externa): `TOTAL_EXECUTED=382`, `FAILED=0`, `DB GATE PASS`.
- **Backend:** ver `docs/work-items/REC2-rbac-asignatura/CLOSURE.md` del repositorio backend (`mvn verify`).

## Rollback

Revertir los commits de BD y backend **juntos**. Revertir solo el backend dejaría las llamadas sin ejecutor y respondería `GEN_002`.
