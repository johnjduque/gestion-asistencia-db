---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC4: aplicar las reglas de estilo de los skills a los SP de John

## Decisión (John, 2026-10-29)

Aplicar las reglas de los skills (ya ajustados en `docs/REC4-ajustar-skills`) **solo a los SP de John**, con cambios de riesgo bajo que no alteren el comportamiento ni el acoplamiento con el backend.

## Alcance: 24 SP

Son los SP creados en las HU de John. Se identificaron por los commits de cada HU.

- **Paquetes 1-4:**
  - plan de estudio: `usp_cambiar_estado_plan_estudio`, `usp_agregar_semestre_plan_estudio`, `usp_quitar_semestre_plan_estudio`;
  - periodos: `usp_actualizar_periodo_academico`, `usp_eliminar_periodo_academico`, `usp_resolver_institucion_gestor_periodo_interno`;
  - decano: `usp_consultar_estudiantes_facultad_paginado`, `usp_consultar_estudiante_facultad_detalle`, `usp_consultar_estructura_facultad`, `usp_consultar_sesiones_facultad_paginado`.
- **HU010/HU011:** `usp_consultar_solicitudes_revision_estudiante`.
- **HU051:** `usp_retirar_estudiante_grupo`, `usp_consultar_destinatarios_retiro_estudiante_grupo`.
- **HU053-HU055 e INT-HU-01:** `usp_registrar_solicitud_ingreso_grupo`, `usp_resolver_solicitud_ingreso_grupo`, `usp_retirar_solicitud_ingreso_grupo`, `usp_consultar_solicitudes_ingreso_grupo_docente`, `usp_consultar_solicitudes_ingreso_estudiante`, `usp_consultar_destinatarios_solicitud_ingreso_grupo`.
- **HU008:** `usp_consultar_oferta_grupos_estudiante`.
- **HU006:** `usp_consultar_perfil_usuario`.
- **HU094/HU095:** `usp_consultar_historial_grupos_docente_programa`, `usp_consultar_resumen_docentes_programa`.
- **REC2:** `usp_validar_gestion_asignatura_coordinador_interno`.

Ninguno está congelado. Todos tienen prueba: 22 con prueba directa y los 2 internos a través de sus SP públicos.

## Cambios (rama `chore/REC4-estilo-sp-john`, sobre `chore/REC4-comentarios-paso`)

| Regla del skill | Antes | Después | Cómo se hizo sin cambiar el comportamiento |
|---|---|---|---|
| `DECLARE` solo entre `AS` y el primer `BEGIN` | 117 variables declaradas en el cuerpo, en 22 SP | 0 | Las del **prólogo** (antes de cualquier lógica, salvo `SET NOCOUNT`) se movieron completas con su valor a la cabecera. Las que estaban **tras lógica previa** (`@idEstudiante` en la oferta y `@estadoTransaccionCatch` en el CATCH de 9 SP) pasaron a `DECLARE` en la cabecera más `SET` en el mismo punto: el valor se calcula en el mismo momento que antes. No había `DECLARE` dentro de ciclos ni variables tabla. |
| Todo `IF` con `BEGIN`/`END` | 42 `IF`/`ELSE IF` de una sola sentencia en 9 SP de escritura | 0 | Se envolvió la sentencia. Con una guardia se comprobó que cada bloque tiene **una sola** sentencia, para no meter en el IF una que antes no estaba. |
| Comentarios `-- PASO n` | — | 23 de 24 | Se agregaron en la rama `chore/REC4-comentarios-paso`. El interno que falta no lo exige el skill de internos. |
| `ISNULL`/`COALESCE` | 3 usos | Sin cambio | Todos están en agregaciones (`MAX` y totales), y el skill actualizado los permite. |

**Fuera de alcance**, por decisión pendiente y riesgo medio-alto: cambiar las lecturas directas de tablas (sin bloqueo) por vistas `uv_*`. Son 151 lecturas en 23 SP y no es un cambio de estilo: exige reescribir y revalidar las consultas.

No cambian:
- las firmas, los resultsets, los códigos de mensaje ni el orden de las validaciones;
- el backend, el frontend, las pruebas ni los manifiestos;
- los SP de otros integrantes.

## Verificación

- **Lote 1 (`DECLARE`, 13 SP de lectura):**
  - inventario posterior: 0 `DECLARE` en el cuerpo;
  - revisión del único `SET` que quedó en mitad del cuerpo (`@idEstudiante`);
  - CI de BD: `TOTAL_EXECUTED=386`, `FAILED=0`, `DB GATE PASS`.
- **Lote 2 (`BEGIN`/`END` y `DECLARE` del CATCH, 9 SP de escritura):**
  - quitando comentarios, espacios y los tokens `BEGIN`/`END`, el SQL es idéntico al original en los 9 archivos;
  - la guardia de una sola sentencia por bloque no encontró excepciones;
  - **Error detectado y corregido:** el primer intento envolvió por error la subconsulta de un `ELSE IF EXISTS (` multilínea en `usp_resolver_solicitud_ingreso_grupo`.
    - El despliegue del CI lo detectó como error de sintaxis; nada se ejecutó ni se subió.
    - Ahora el script considera que la condición sigue mientras tenga paréntesis abiertos.
    - Se regeneraron los 9 SP y se revisaron a mano los 8 cambios de ese SP.
  - CI de BD: ver la sección siguiente.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29), con los 24 SP ajustados: `TOTAL_EXECUTED=386`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`.

## Rollback

Revertir los commits de la rama. Son cambios de forma, sin cambios de datos.
