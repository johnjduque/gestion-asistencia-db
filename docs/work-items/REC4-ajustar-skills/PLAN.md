---
status: active
type: work-item
scope: db-docs
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC4: ajustar los skills de BD a la práctica vigente

## Contexto

La auditoría de la BD contra los skills (2026-10-28) encontró 14 diferencias entre los `.agents/skills/*/SKILL.md` y el código vigente. El informe de revisión es `informes/SKILLS_BD_ACTUALES_2026-10-29.md`, fuera del repo.

John revisó los skills y concluyó que están bien planteados. Decidió (2026-10-29):

- ajustar **solo el texto** de los skills donde el código se aparta **a propósito**, por corrección o seguridad;
- **mantener** las reglas de estilo (`DECLARE` en la cabecera y `-- PASO n`) para el código nuevo;
- no reescribir el código anterior solo por estilo;
- **no tocar AGENTS.md**.

## Cambios (solo `.agents/skills/*.md`; sin cambios en `schema/`, `test/` ni AGENTS.md)

| # | Desviación | Skill | Ajuste |
|---|---|---|---|
| A1 | `uv_auth_*` con contexto NULL | `vista-consulta-con-validaciones` §3 y su ejemplo; `cobertura-pruebas-objetos-bd` | El estándar pasa a ser **fail-closed**: sin contexto, 0 filas (`IS NOT NULL AND (...)`), como en las 9 vistas vigentes. La prueba de contexto nulo espera 0 filas. |
| A2 | `XACT_ABORT` en SP con savepoint | `procedimientos-externos-condiciones` | Se distinguen los dos patrones: transacción simple (`XACT_ABORT ON` y `XACT_STATE()`) y transacción propia o savepoint (sin `XACT_ABORT`; `Msg 3930`, REC3). |
| A3 | `ISNULL`/`COALESCE` | externos e internos | Siguen prohibidos para parámetros; se permiten solo en agregaciones. |
| A4 | SP de lectura | `procedimientos-externos-condiciones` | Se documenta el patrón READ_QUERY_RESULTSET (validar, `THROW` con código de catálogo y filas). Los SP que escriben conservan el resultset de 4 columnas. |
| A5 | Internos de resolución | `procedimientos-internos-condiciones` | Variante con OUTPUT propio y `THROW`, solo para SP de lectura. |
| A6 | Ejemplos inexistentes | `modelo-jerarquico-rbac` y `procedimientos-externos-condiciones` | `usp_aprobar_docente_grupo` y `usp_aprobar_matricula_estudiante` (no existen en `schema/`) se reemplazan por `usp_vincular_docente_programa` y `usp_resolver_solicitud_ingreso_grupo`. |
| B7 | Titularidad dentro del SP | `modelo-jerarquico-rbac` §4 | Alternativa aceptada si se exige el ejecutor y se responde `SEC_001`/`SEC_002`. |
| B8 | Validación compartida | `modelo-jerarquico-rbac` §4 e internos | Se recomienda un `usp_validar_*_interno` compartido; ejemplo de REC2. |
| C | Lectura por vistas y organización de pruebas | `consulta-a-bd`, externos, internos y `cobertura-pruebas-objetos-bd` | Excepción para lecturas con `UPDLOCK`/`HOLDLOCK` dentro de una transacción. Se aceptan pruebas agrupadas por HU si están en `test_suite.sql` y emiten `TEST_PASS`. |
| Estilo | `DECLARE` en la cabecera y `PASO n` | externos e internos | **Se mantienen** como obligatorios en el código nuevo. El código anterior se ajusta solo cuando se modifica por otra razón. |

No se cambian:
- las reglas que se cumplen al 100 % (nombres, un objeto por archivo, 4 columnas en los SP que escriben, UUID con prefijo `id`, sin SQL dinámico);
- el skill `consistencia-tablas`.

**Fuera de alcance:**
- el `SELECT` del runtime sobre las vistas base (decisión de Alejo);
- los `TEST_PASS` que faltan en 9 suites de catálogos (son de Sergio).

## Comentarios `-- PASO n` (rama aparte)

Se agregan en una rama separada, `chore/REC4-comentarios-paso`, solo en los SP **no congelados**. Ese cambio solo toca líneas de comentario, y su work item verifica que el SQL sin comentarios queda idéntico.

## Validación

- Rama solo de documentación: sin cambios en `schema/`, `test/` ni contratos.
- Se verificó que ningún skill nombra un SP inexistente.
- Los ejemplos citados existen en `schema/`.
