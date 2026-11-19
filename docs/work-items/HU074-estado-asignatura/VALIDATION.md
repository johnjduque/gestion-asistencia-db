---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# VALIDATION — HU074: activar o inactivar asignaturas

Fecha: 2026-11-19. Equipo local (Windows 10, 8 GB de RAM, Docker Desktop). Rama `feat/HU074-HU178-asignatura-estado-ambito`.

## Base local `sql_server_asistencias`

| Paso | Resultado |
|---|---|
| `scripts/migrar.ps1 -Modo Aplicar` | La 57 se aplicó (`MIGRAR_APLICADA_AHORA 57_hu074_estado_asignatura_reglas`); estado final `total=57 registradas=57 pendientes=0 deriva=0` |
| `test/test_hu074_migracion.ps1` (up → down → up en una transacción revertida) | `HU074_MIG_UP_DOWN_UP` PASA; después la base conserva la 57 (interno, 4 mensajes, regla en el toggle) |
| `test/test_hu074_estado_asignatura.sql` | 12/12 PASAN (`HU074_01..11`, `HU074_TRANCOUNT_ZERO`) |
| Pruebas que usan los SP tocados | `SUBJECT_TOGGLE` (ajustada), `REC2_RA04_COORDINADOR_TITULAR_OK`, `CULM001_B2NM_OFERTA_Y_DECANO` y `CULM001_B2NM_ASIGNATURA_PLAN` PASAN |

### Ajustes de la revisión independiente (2026-11-19): idempotencia y carrera

Cambios: `@estaActivaDeseada BIT = NULL` en el toggle; transacción con `UPDLOCK, HOLDLOCK` en el toggle y en `usp_crear_grupo` (`usp_validar_asignatura_activa_interno @bloquearFila = 1`); `SET XACT_ABORT ON` en ambos. La 57 se reaplicó en la base local con el mecanismo del repositorio: down manual (`57_..._down.sql` y borrado de su fila en `dbo.MigracionAplicada`, como indica `scripts/migrar.ps1`) y `scripts/migrar.ps1 -Modo Aplicar`.

| Paso | Resultado |
|---|---|
| `scripts/migrar.ps1 -Modo Aplicar` tras el down | `MIGRAR_APLICADA_AHORA 57_hu074_estado_asignatura_reglas`; `-Modo Estado`: `total=57 registradas=57 pendientes=0 deriva=0` |
| `test/test_hu074_migracion.ps1` | `HU074_MIG_UP_DOWN_UP` PASA (ahora también verifica `@estaActivaDeseada` y el bloqueo de fila tras el up, y su ausencia tras el down) |
| `test/test_ata_k_migracion.ps1` | `ATA_K_MIG_UP_DOWN_UP` PASA |
| `test/test_hu074_estado_asignatura.sql` | 19/19 PASAN (`HU074_01..18`, `HU074_TRANCOUNT_ZERO`) |
| SP tocados, archivo por archivo | `test_subject_catalog` 7/7 (incluye `SUBJECT_TOGGLE`), `test_rec2_rbac_asignatura` 5/5 (incluye `REC2_RA04`), `test_culm001_b2nm_*` (oferta_y_decano, asignatura_plan, ambito_grupo_mixto, coordinador_dos_programas, matricula, compilacion) 6/6, `test_dec073_validaciones` 8/8, `test_cruce_horario_docente` 6/6, `test_reactive_academic` 7/7, `test_usp_guardar_horarios_grupo` 7/7, `test_usp_cambiar_estado_docente_programa` 5/5, `test_mrm_solicitud_sesion` 15/15 |
| `test_usp_crear_actualizar_grupo.sql` | Suelto se corta por la intercalación de `tempdb` (Msg 468 en `#grupoResultado`, causa previa). Con una copia temporal que solo agrega `COLLATE DATABASE_DEFAULT` a esa tabla: 3/3 (`GROUP_CREATE`, `GROUP_UPDATE`, `GROUP_CAPACITY_REJECT`) |
| `test_usp_precargar_sesiones_grupo.sql` | Suelto falla por un fixture de la suite (`#culm001_b2_crear_toma`, ajeno). Con `test/fixtures/culm001_b2_toma_fixture.sql` antes: 16/16 |
| Transacción propia (sin transacción del llamador) | Toggle con `@estaActivaDeseada` igual al estado actual: `ASI_011`, sin cambio, `@@TRANCOUNT = 0`. `usp_crear_grupo` rechazado después del PASO 2B (docente inexistente, `DOC_001`): sin grupo, `@@TRANCOUNT = 0` |
| Concurrencia | Sesión A: toggle dentro de una transacción abierta 6 s (fila bloqueada). Sesión B: `usp_crear_grupo` sobre la misma asignatura esperó ~4,2 s hasta que A liberó la fila |
| `freeze-manifest -Mode Verify`, `lb004d-manifest -Mode Verify`, `generar-catalogo-mensajes -Check` | OK (`culm001_d=81`; ningún archivo cubierto cambió en este ajuste), OK, OK (492 códigos) |
| `scripts/freeze-manifest.ps1 -Mode Verify` | OK (`culm001_d=81`; se actualizó el hash de `scripts/migrar-marcadores.json`) |
| `scripts/lb004d-manifest.ps1 -Mode Verify` | OK |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | OK (492 códigos; antes 488) |
| Subcadena prohibida en `schema/`, `test/` y `migrations/` nuevos o cambiados | 0 apariciones |

### Compuerta completa sobre la base local

`test_summary.ps1` (sin `test_val_migrar_detectar.ps1`, que corre el CI) **no queda verde en esta instancia por una causa previa y
ajena a HU074**: `tempdb` y las bases de sistema del contenedor están en `Modern_Spanish_CI_AS` y la base en
`SQL_Latin1_General_CP1_CI_AS` (ver `docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md`, "Nota: intercalación"). La suite SQL se
detiene en `test_consultas_decano_facultad` (T-104-01, `Msg 468 Cannot resolve the collation conflict`) y los runners up/down/up
de otras migraciones fallan con el mismo error. Resultado de esa corrida: `TOTAL_EXPECTED=836`, `PASSED=197`, `FAILED=25`,
`CRITICAL_MISSING=661` (los que no llegaron a ejecutarse tras el corte), `SKIPPED=1` (permitido). Ningún fallo toca objetos de HU074;
todas las pruebas de HU074 y las ajustadas pasaron en esa misma corrida.

### Compuerta en contenedor desechable

Se intentó repetir la compuerta en un contenedor SQL Server 2022 desechable con `MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS`
(como en MEJORAS-SERGIO). Docker Desktop dejó de responder (errores 500 y comandos colgados; el equipo quedó con ~550 MB libres).
**Pendiente:** correr la compuerta completa en un contenedor desechable con esa intercalación (o en el CI del PR) y anotar aquí los
números; retirar el contenedor `qa_hu074_sql` si quedó creado.

### Renumeración a la migración 58 (2026-11-19, integración de develop con NOTOMA-001)

El PR #153 (NOTOMA-001) ocupó en develop la migración 57 (`57_notoma_aviso_sesion_sin_toma`) y el seed 69. HU074 pasa a
`migrations/58_hu074_estado_asignatura_reglas_up|down.sql` y `schema/seed/70_hu074_mensajes_estado_asignatura.sql` (mismo contenido;
solo cambian nombres y referencias). NOTOMA-001 no cambia `usp_toggle_estado_asignatura`, `usp_crear_grupo` ni
`usp_asociar_asignatura_plan`, así que el down conserva el texto de develop. En la base local se ejecutó el down de HU074, se borró
la fila `57_hu074_estado_asignatura_reglas` de `dbo.MigracionAplicada` y `scripts/migrar.ps1 -Modo Aplicar` aplicó la 57 de NOTOMA y la 58.

| Paso | Resultado |
|---|---|
| `scripts/migrar.ps1 -Modo Aplicar` | `MIGRAR_APLICADA_AHORA 57_notoma_aviso_sesion_sin_toma` y `58_hu074_estado_asignatura_reglas`; `-Modo Estado`: `total=58 registradas=58 pendientes=0 deriva=0` |
| `test/test_hu074_estado_asignatura.sql` | 19/19 PASAN |
| `test/test_hu074_migracion.ps1` | `HU074_MIG_UP_DOWN_UP` PASA |
| `test/test_notoma_aviso_sin_toma.sql`, `test/test_notoma_migraciones.ps1` | 10/10 PASAN; `NOTOMA_MIG_UP_DOWN_UP` PASA |
| `test/test_contract_closure.sql`, `test/test_culm001_d3_parametros.sql` | 19/19 y 20/20 PASAN |
| `freeze-manifest -Mode Verify`, `lb004d-manifest -Mode Verify`, `generar-catalogo-mensajes -Check` | OK (`culm001_d=81`, hash de `scripts/migrar-marcadores.json` actualizado), OK, OK (492 códigos) |

## Corrección VAL_MDET_06 / VAL_MDET_07 (2026-11-19, PR #154)

- **Falla en el CI:** VAL_MDET_06_APLICAR_EN_ORDEN y VAL_MDET_07_TRAS_APLICAR_TODAS daban «Invalid column name 'estado'» al aplicar las migraciones en orden sobre una base temporal.
- **Causa:** la regla `ASI_009` de la 58 usa `uv_periodo_academico.estado`, pero esa columna (CIERRE-W2A) llegó al esquema sin migración propia.
- **Corrección:** la up de la 58 recompila `uv_periodo_academico` (texto de `schema/views/uv_periodo_academico.sql`) antes del interno y de los SP. Ahora el encabezado tiene el punto 5.
- **BD local:** se reaplicó la 58 (down, borrar la fila de `MigracionAplicada` y `migrar.ps1 -Modo Aplicar`). Resultado: total=58, registradas=58, pendientes=0, deriva=0.
- **Verificación:** VAL_MDET_* en el CI del PR #154.

## Pendiente

- Compuerta completa verde (ver arriba) y `VAL_MDET_*` en el CI.

El backend ya clasifica `ASI_009` y `ASI_010` como `CONFLICT` (409) con su propio code (`DbFailureClassifier.classifyDbCode`); ya no es un pendiente.
