---
status: active
type: work-item
scope: db
owner: database-team
last-reviewed: 2026-11-19
---

# CONTRACT — SES-GEN-01: calendario de sesiones del semestre

Esta decisión contractual incorpora una capacidad de negocio post-freeze. No modifica firmas ni resultsets canónicos existentes y no cambia los objetos del Golden Path del baseline. La aprobación de preparar este cambio quedó expresada en la solicitud de alistamiento del PR #155 (2026-11-19); la revisión del PR por el owner de BD sigue siendo necesaria antes de fusionar.

## Extensión física del modelo

- `dbo.Asignatura.horasSemanales INT NULL`, nullable para asignaturas sin carga; cuando tiene valor, es un entero positivo y `CK_Asignatura_horasSemanales` lo valida.
- Rango de negocio `1..ASIGNATURA/HORAS_SEMANALES_MAXIMO` (40 por defecto), validado en creación y actualización con `ASI_013`.
- La proyección `dbo.uv_asignatura` expone el dato al final de su resultado existente de esta rama.
- `dbo.uv_periodo_academico_cierre` es una proyección interna mínima de `id` y `fechaCierreUtc`; no recibe permiso `SELECT` para `rol_asistencias_runtime`.
- Ningún nombre o tipo de columna preexistente cambia. La migración explícita es `59_ses_gen_01_calendario_semestre_up|down.sql`; el número 57 pertenece a NOTOMA-001 y el 58 a HU074.

## Manifiesto de integridad

`schema/seed/62_val_mensajes_aplicacion.sql` y `scripts/migrar-marcadores.json` ya están registrados como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`; sus hashes se actualizan con SES-GEN-01. `DB_BASELINE_CONTRACT.md`, `DB_BASELINE_CONTRACT.sha256` y `DB_DEVELOP_FREEZE_MANIFEST.sha256` permanecen intactos.

## Semestre

- Un período nuevo o editado en fechas dura exactamente 16 semanas corridas (112 días, extremos incluidos); un cambio solo de nombre no altera ni revalida las fechas históricas.
- El período para crear el grupo es obligatorio, vigente, no cerrado y de la institución de los programas custodiados por el coordinador. No se elige el más reciente si falta; falla con `VAL_002` o `PER_010` según el caso.
- `PER_011` representa duración distinta de 112 días.

## Horario y sesiones

- La suma de minutos semanales del horario coincide exactamente con `horasSemanales * 60` si la asignatura tiene horas configuradas (`HOR_006`).
- Cada franja respeta duración mínima/máxima y ventana local (`HOR_007`, `HOR_008`).
- La semana de sesión se calcula en bloques de siete días a partir del inicio del período; la precarga genera hasta 16 semanas y mantiene sus reglas de idempotencia y conservación.
- `dbo.usp_previsualizar_horario_grupo` es lectura (`READ_QUERY_RESULTSET`): una fila `RESUMEN` y filas discriminadas `FRANJA`, `SESION`, `FESTIVO` y `CONFLICTO`. Los conflictos son filas de datos; los insumos inválidos o el ámbito inválido se propagan como `THROW 51000` con código de catálogo.
- Los códigos de conflicto HOR_006..HOR_014 conservan las severidades y mensajes de `schema/seed/04_mensaje.sql`.

## Alta de grupo, RBAC y colisiones

- Solo el perfil COORDINADOR crea el grupo. Después de la validación RBAC, una asignatura inactiva se rechaza con `ASI_010` (HU074). Una asignatura activa sin vínculo/plan activo válido o que incluye un programa fuera de custodia se rechaza con `ASI_014`.
- La fila de asignatura se bloquea con `UPDLOCK, HOLDLOCK` desde la validación de estado hasta el `INSERT`, dentro de transacción propia o de la transacción del llamador. `usp_toggle_estado_asignatura` usa el mismo bloqueo.
- `ASI_009` sigue reservado a HU074 (inactivación bloqueada por grupos activos); `ASI_010` sigue reservado a asignatura inactiva. SES-GEN-01 usa `ASI_013` para horas inválidas y `ASI_014` para vínculo/ámbito.
- Los demás códigos nuevos son `PER_010`, `PER_011` y `HOR_006..HOR_014`; se cargan tanto en catálogo de usuario como técnico. `VAL_APP_076` ya pertenece al catálogo general y no se elimina con el rollback de SES-GEN-01.

## Permisos

- `rol_asistencias_runtime` recibe solo `EXECUTE` en `usp_previsualizar_horario_grupo` mediante `rol_asistencias_runtime_ses_gen_01.sql`.
- No se conceden permisos sobre tablas base ni `SELECT` sobre `uv_periodo_academico_cierre`.

## Pruebas contractuales

- `test/test_ses_gen_01_calendario_semestre.sql`: duración, edición, B1/B2, horas semanales, ventana/franjas y paridad de calendario entre preview y precarga.
- `test/test_ses_gen_01_migracion.ps1`: migración 59 up→down→up, conservación de ASI_009/ASI_010 y rollback.
- `SES_GEN_01_RUNTIME_GRANT` en `test/test_public_objects.sql` y exclusión de READ_QUERY_RESULTSET en `test/test_contract_closure.sql`.
- El runner oficial registra estos IDs en `test_summary.ps1`.
