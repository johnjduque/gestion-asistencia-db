---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC4: comentarios `-- PASO n` en SP no congelados

## Contexto

La regla de estilo de `procedimientos-externos-condiciones` (comentarios `-- PASO n`) se mantiene para el código nuevo. La auditoría de la BD (2026-10-28) encontró 58 SP públicos sin esos comentarios.

John decidió (2026-10-29) organizarlos **solo** en los SP no congelados y **sin cambiar ni una línea de código**. Los 6 SP congelados que tampoco los tienen quedan como están.

## Cambio

- **Alcance:** 52 SP no congelados.
  - Se insertaron 296 comentarios `-- PASO n: <descripción>` antes de cada paso principal del cuerpo.
  - En 11 casos ya había un comentario descriptivo justo encima del paso: se conservó su texto y solo se le antepuso `PASO n:`.
- **Origen de las descripciones:**
  - Se generaron a partir del contenido de cada paso: validación de correlación, ejecutor obligatorio (`GEN_002`), RBAC con el perfil, titularidad con la entidad, resolución de ámbito con el interno usado, validación de negocio con su código de catálogo, escritura con la tabla, contexto `uv_auth_*` y consulta final.
  - Se revisaron los casos genéricos y se les dio una descripción específica.
- **No se tocaron:**
  - las líneas de código, los `DECLARE`, los espacios de las sentencias y la indentación del código;
  - los SP congelados (manifiestos `docs/contracts/*.sha256`);
  - los manifiestos, las pruebas y `schema/` fuera de los 52 archivos.

## Excepción por SonarCloud (PR #66, 2026-10-29)

**Qué pasó:** el Quality Gate del PR rechazó un **8.8 % de duplicación en código nuevo** (26 líneas de 296; el límite es 3 %).

**Causa:** en 8 SP ya había bloques casi idénticos entre sí desde antes de este cambio, por ejemplo:
- `usp_actualizar_programa_academico` y `usp_cambiar_estado_programa_academico`;
- `usp_crear_area` y `usp_crear_tipo_programa`;
- los dos de destinatarios.

Sonar no los contaba porque eran código viejo. Al insertar un comentario dentro de esos bloques, esas líneas pasaron a ser "nuevas" y se contaron como duplicación nueva.

**Decisión de John (opción A):** esos 8 SP vuelven a su estado de `develop`, sin comentarios PASO. No se cambió la configuración compartida de Sonar.

**SP excluidos:**
- `usp_actualizar_programa_academico`
- `usp_cambiar_estado_programa_academico`
- `usp_crear_area`
- `usp_crear_tipo_programa`
- `usp_consultar_detalle_solicitud_revision_docente`
- `usp_consultar_solicitudes_revision_estudiante`
- `usp_consultar_destinatarios_retiro_estudiante_grupo`
- `usp_consultar_destinatarios_solicitud_ingreso_grupo`

**Alcance final:** **44 SP con 246 comentarios PASO.** Esos 8 SP se pueden ajustar más adelante si se elimina la duplicación de fondo, por ejemplo con un interno compartido como en REC2.

## Verificación de que el cambio es solo de comentarios

1. **Script generador:** al quitar las líneas `-- PASO n:` insertadas y revertir el prefijo de los 11 comentarios convertidos, se obtiene el archivo original línea por línea. Resultado: 52/52 OK.
2. **Verificación independiente con `git`:** el SQL sin líneas de comentario es idéntico al de `develop` en los 52 archivos. En el diff hay **0 líneas de código** cambiadas.
3. **Manifiesto:** `freeze-manifest -Mode Verify` da OK y ningún archivo congelado aparece en el diff.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29): `TOTAL_EXECUTED=386`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`, `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED`.

## Rollback

Revertir el commit. Al ser solo comentarios, no afecta datos ni el comportamiento.
