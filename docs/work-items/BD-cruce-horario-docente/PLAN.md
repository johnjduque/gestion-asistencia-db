---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — Cruce de horario del docente (opción A)

## Decisión

John (2026-10-29): **un docente no puede tener dos grupos a la misma hora.** Esa era la intención de `usp_validar_cruce_horario_docente_interno`, que había quedado sin caller. Se eligió la opción A del análisis de impacto (informe `informes/ANALISIS_CRUCE_HORARIO_DOCENTE_2026-10-29.md`, fuera del repo).

## Contexto

- Hoy la tabla `Horario` solo se llena desde los seeds: ningún SP ni endpoint la escribe.
- La regla aplica cuando **cambia el titular** de un grupo que ya tiene horario.
- `usp_crear_grupo` no puede generar un cruce, porque el grupo nace sin horario: `Horario.grupo` es FK a `Grupo`. La validación al crear queda para el SP que en el futuro guarde horarios (opción B).
- Las sesiones (`usp_crear_sesion*`, `usp_actualizar_sesion_v2` y `usp_generar_sesiones_grupo`) están congeladas y **no se tocan**.

## Cambios

1. **`usp_validar_cruce_horario_docente_interno`:**
   - el mensaje `HOR_002` recibe el nombre del grupo en conflicto y la franja (`Lunes 08:00-10:00`); el técnico agrega el `idGrupo` evaluado;
   - `ORDER BY` determinista en el `TOP 1`;
   - deja de invocar `usp_validar_grupo_exista_para_docente_interno`. Ese interno exige que el grupo esté en el período vigente, y eso habría impedido cambiar el titular de un grupo del semestre siguiente. La existencia del grupo ya la valida `usp_actualizar_grupo` (PASO 2). Con este cambio `usp_validar_grupo_exista_para_docente_interno` queda sin callers; su eliminación queda a decisión de John;
   - la lógica de traslape no cambia: mismo día y período, `inicio1 < fin2 AND fin1 > inicio2`, sin contar el propio grupo.
2. **`usp_actualizar_grupo` (PASO 3C):** si cambia el titular, invoca la validación con el docente nuevo antes del `UPDATE`. Si el titular no cambia, no se revalida (mismo criterio que el PASO 3B, DOC_009). No cambian ni la firma ni el resultset.
3. **Catálogo (`schema/seed/04_mensaje.sql`):** cambian los textos de `HOR_002`, usuario y técnico, ahora con marcadores `{}`. `docs/catalogos/catalogo-mensajes.md` se regeneró con `scripts/generar-catalogo-mensajes.ps1`.
4. **Pruebas:** nueva suite `test/test_cruce_horario_docente.sql`, registrada en `test_suite.sql`. Sus IDs son requeridos en `test_summary.ps1`.
5. **Backend** (rama `fix/cruce-horario-docente`):
   - `DbFailureClassifier` traduce `HOR_002` a `GrupoErrorCode.ERR_CRUCE_HORARIO_DOCENTE` (`CONFLICT`, HTTP 409). Antes caía en `ERR_DB_UNCLASSIFIED` (500);
   - caso nuevo en `DbExceptionTranslatorTest`.
6. **Documentación:**
   - ficha del interno en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md`;
   - SP-002 en `transaccion-procedimiento.md`;
   - fila de `usp_actualizar_grupo` en `especificacion_sp_endpoints.md`.

## Matriz de pruebas

| ID | Escenario | Esperado |
|---|---|---|
| `TEACHER_SCHEDULE_CREATE_ALLOWED` | Crear grupos (nacen sin horario) | Éxito |
| `TEACHER_SCHEDULE_CONFLICT_REJECTED` | Cambiar el titular de B (lunes 09-11) al docente que tiene A (lunes 08-10) | `HOR_002` con "Grupo QA Cruce A" y "Lunes 08:00-10:00"; B conserva su titular |
| `TEACHER_SCHEDULE_ADJACENT_ALLOWED` | Lunes 10-12 contra lunes 08-10 | Éxito (las horas contiguas no son cruce) |
| `TEACHER_SCHEDULE_OTHER_DAY_ALLOWED` | Martes 08-10 contra lunes 08-10 | Éxito |
| `TEACHER_SCHEDULE_OTHER_PERIOD_ALLOWED` | Lunes 08-10 en otro período | Éxito |
| `TEACHER_SCHEDULE_SAME_TITULAR_ALLOWED` | Editar el cupo sin cambiar el titular | Éxito, sin revalidar |
| Backend `HOR_002 → ERR_CRUCE_HORARIO_DOCENTE` | `DBCODE=HOR_002` | `ConflictException` (409) |

## Pendiente (opción B, con las observaciones de sesiones)

- Guardar el horario del grupo: SP nuevo que invoque esta validación, endpoint y conexión del formulario del frontend, que hoy pide días y horas pero no los envía.
- Si se quiere la regla también por sesión, se necesitan cambios en SP congelados y la aprobación de John y José Alejandro.

## Coordinación

Toca `usp_actualizar_grupo` y `usp_validar_cruce_horario_docente_interno`, ambos de Sergio. Hay que avisarle antes del merge.
