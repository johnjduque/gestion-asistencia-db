---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# PLAN — HU074: activar o inactivar asignaturas

## Identidad y objetivo

- **HU074:** el coordinador activa o inactiva una asignatura del catálogo. Hasta ahora `usp_toggle_estado_asignatura` alternaba `Asignatura.estado` sin reglas y el estado no tenía efecto en ningún otro lado.
- **Reglas nuevas:**
  1. No se inactiva una asignatura que tenga grupos en el período vigente o en uno futuro, de cualquier programa (`ASI_009`). Reactivar siempre se permite.
  2. Una asignatura inactiva no se usa para crear grupos ni se asocia a un plan (`ASI_010`). Los grupos existentes no cambian.
  3. Mensajes de éxito propios: `ASI_011` (quedó activa) y `ASI_012` (quedó inactiva), en lugar del genérico `GEN_004`.
- La regla de ámbito no cambia: quien inactiva debe coordinar todos los programas con vínculo activo de la asignatura (`ASI_006`, regla S2 de CULM-001 B2NM).
- Contrato: [CONTRACT.md](CONTRACT.md). Pruebas: [TEST_PLAN.md](TEST_PLAN.md). Validación: [VALIDATION.md](VALIDATION.md).

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `schema/seed/69_hu074_mensajes_estado_asignatura.sql` | Nuevo: mensajes `ASI_009`..`ASI_012` (usuario y técnico, MERGE idempotente) |
| `usp_validar_asignatura_activa_interno` | Nuevo interno de validación compartido (`ASI_010`); `@bloquearFila BIT = 0` (1: lee la fila con `UPDLOCK, HOLDLOCK`); sin `EXECUTE` para el runtime |
| `usp_toggle_estado_asignatura` | `ASI_009` al inactivar con grupos vigentes o futuros; `ASI_011` / `ASI_012` en el éxito; parámetro aditivo `@estaActivaDeseada BIT = NULL` (idempotente); transacción con la fila bloqueada. Resultset sin cambio |
| `usp_crear_grupo` | PASO 2B: `ASI_010` con una asignatura inactiva; del PASO 2B al `INSERT` en una transacción con la fila de la asignatura bloqueada. Firma y resultset sin cambio |
| `usp_asociar_asignatura_plan` | `ASI_010` con una asignatura inactiva (antes caía en `GEN_001`). Firma y resultset sin cambio |
| `migrations/57_hu074_estado_asignatura_reglas_up.sql` y `_down.sql` | Up: mensajes, interno y los tres SP. Down: textos de develop de los tres SP, retira el interno y los mensajes |
| `scripts/migrar-marcadores.json` | Marcadores de la 57 (y su hash en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`) |
| `test/test_hu074_estado_asignatura.sql`, `test/test_hu074_migracion.sql`, `test/test_hu074_migracion.ps1` | Nuevos (19 casos + up/down/up) |
| `test/test_subject_catalog.sql` | `SUBJECT_TOGGLE` espera `ASI_012` / `ASI_011` en lugar de `GEN_004` |
| `test_suite.sql`, `test_summary.ps1` | Registro de las pruebas nuevas |

Sin cambios de tablas, vistas ni permisos.

## Decisiones

- **"Vigente o futuro":** se reutiliza la regla de fechas que ya usa el repositorio: `uv_periodo_academico.estado` (fecha local institucional, `TIEMPO/ZONA_HORARIA_SQLSERVER`) distinto de `CERRADO`, es decir `fechaFin >= hoy`. Es la misma condición de `ASI_005` en `usp_desvincular_asignatura_plan`. No se inventa otra.
- **Grupos que cuentan:** todos. `Grupo` no tiene baja lógica ni estado propio (`grupoEstaHablitado` de `uv_grupo` es derivado de las fechas del período).
- **Idempotencia (`@estaActivaDeseada BIT = NULL`, aditivo al final de la firma):** `NULL` conserva el comportamiento de alternar el estado leído. Con `1` o `0` fija ese estado; si la asignatura ya está en él responde éxito sin cambios (`ASI_011` si activa, `ASI_012` si inactiva) y no evalúa la regla de grupos. Pedir `0` sobre una activa aplica `ASI_009`. Un reintento del cliente no invierte lo que ya se hizo.
- **Carrera inactivar vs crear grupo (resuelta):** el toggle (`SET XACT_ABORT ON`) abre transacción (o usa la del llamador, patrón `@transaccionPropia`), lee la fila de `dbo.Asignatura` con `UPDLOCK, HOLDLOCK`, busca grupos y hace el `UPDATE` dentro de ella. `usp_crear_grupo` (`SET XACT_ABORT ON`) abre su transacción en el PASO 2B y valida `ASI_010` con `usp_validar_asignatura_activa_interno @bloquearFila = 1`, que toma el mismo bloqueo, hasta el `INSERT` del PASO 7 (`COMMIT` si inserta; `ROLLBACK` en las ramas de rechazo, que no escriben). Ambos toman primero el bloqueo de la asignatura, así que se serializan sin interbloqueo: si gana el toggle, el grupo ve la asignatura inactiva (`ASI_010`); si gana la creación, el toggle ve el grupo (`ASI_009`). Verificado en la base local: una creación lanzada mientras otra sesión tenía la fila bloqueada esperó ~4,2 s hasta que se liberó.
- **Asociables (`usp_consultar_asignaturas_asociables_paginado`):** ya excluía las inactivas (`estaActivaAsignatura = 1`). Se conserva así, para no ofrecer algo que luego se rechaza con `ASI_010`. Igual la oferta de creación de grupo del docente (`usp_consultar_oferta_creacion_grupo_docente`).
- **Malla (`usp_consultar_asignaturas_plan_paginado` sobre `uv_asignatura_plan_estudio`):** ya expone `estaActivaAsignatura = Asignatura.estado` y no filtra las inactivas; el coordinador las ve para reactivarlas. No cambia ninguna columna.
- **Otros caminos de creación de grupo:** en `schema/` el único `INSERT` en `dbo.Grupo` está en `usp_crear_grupo` (el docente ya no crea grupos, DEC-065 (4); no hay duplicación ni importación de grupos). `usp_actualizar_grupo` no cambia la asignatura de un grupo existente, así que no aplica.
- **Interno compartido:** la validación `ASI_010` vive en `usp_validar_asignatura_activa_interno` para no repetir el bloque en los dos SP (duplicación de Sonar).

## Backend

El mensaje técnico llega como `DBCODE=ASI_009|...`, `DBCODE=ASI_010|...`, `DBCODE=ASI_011|...` y `DBCODE=ASI_012|...` (más ` Correlacion: <guid>`), igual que `ASI_006`. El backend los clasifica en `DbFailureClassifier.classifyDbCode`: `ASI_006`, `ASI_009` y `ASI_010` → `CONFLICT` (409) con su propio code. Para usar la idempotencia, el backend puede enviar `@estaActivaDeseada` (opcional; sin él, el SP alterna como antes).
