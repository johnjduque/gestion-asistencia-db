# DB Develop Freeze Addendum (DB-GP-001C)

Complementa, **sin reemplazar**, `docs/contracts/DB_BASELINE_CONTRACT.md`.

```text
FINAL_DEVELOP_COMMIT: dcc69f19ffe3c246b78fa1996299ad97df229bbf
  (ultimo commit que cambia esquema/tests/gates; los commits posteriores son solo documentacion)
BASE_COMMIT_BEFORE_HARDENING: c30ecc56a070ae9c9de01e02b2f3f43f6a474abd
BASELINE_CONTRACT_SHA: 45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec
BASELINE_CONTRACT: UNCHANGED
GOLDEN_PATH: FROZEN

NON_GOLDEN_PATH_EXTENSIONS:
  - uv_auth_*  (12 vistas)
  - ufn_obtener_usuario_ejecutor_contexto
  - ufn_obtener_perfil_usuario_contexto
  - usp_establecer_contexto_usuario_ejecutor
  - usp_consultar_grupos_paginado

AUTH_VIEW_POLICY: FAIL_CLOSED
NULL_CONTEXT: NO_ROWS
UNKNOWN_CONTEXT: NO_ROWS
SESSION_CONTEXT_RESTORE: REQUIRED
PAGINATION: NOT_CONSUMED_BY_GOLDEN_PATH_BACKEND
JPA_PILOT: USES FROZEN BASE VIEWS, NOT uv_auth_*
DB_PRINCIPAL_HARDENING: FUTURE_DECISION
DB SCHEMA CHANGE AFTER FREEZE: REQUIRES NEW WORK ITEM / CONTRACT DECISION
```

## Semantica congelada

- `uv_*` = interna/base (datos completos, mantenimiento). `uv_auth_*` = externa autorizada, **fail closed**.
- `SESSION_CONTEXT` es estado de la conexion fisica: debe restaurarse; el backend/JPA futuro debe disenar su ciclo de vida
  por conexion antes de usar `uv_auth_*`. Ver `docs/arquitectura/DB_SESSION_CONTEXT_Y_VISTAS_AUTORIZADAS.md`.
- `usp_consultar_grupos_paginado`: `NON_GOLDEN_PATH_EXTENSION`, `NOT_BACKEND_CONSUMED`, `NOT_PART_OF_LB002_JPA_PILOT`,
  resultset `READ_QUERY_RESULTSET` (no `MUTATION_COMMAND_RESULTSET`).
- El backend puede depender solo del contrato aprobado; una extension requiere un work item de alineacion que la adopte.

## Manifest

`docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256` registra SHA-256 (CRLF normalizado a LF, igual al blob de Git) del contrato
y de las fuentes Golden Path (5 vistas + 4 SP de sesion/asistencia). Se genera y verifica con:

```powershell
./scripts/freeze-manifest.ps1 -Mode Generate   # solo tras una decision autorizada de contrato/freeze
./scripts/freeze-manifest.ps1 -Mode Verify     # ejecutado por test_summary.ps1 (GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED)
```

Equivalente manual por archivo: `git show <commit>:<ruta> | sha256sum`.

## Revision post-freeze LB-002.1C-A (2026-09-27)

Registro de un avance del tip posterior al freeze. **No reescribe** los valores de arriba (`FINAL_DEVELOP_COMMIT` sigue siendo el ultimo commit de la fase DB-GP-001C).
Detalle y evidencia: `docs/work-items/LB-002.1C-A-db-contract-baseline-recovery/REPORT.md`.

```text
PREVIOUS FROZEN TIP:   9b2b993 (docs)  /  dcc69f19ffe3c246b78fa1996299ad97df229bbf (FINAL_DEVELOP_COMMIT)
BASE SHA:              6c120ca5b3eea191924163472b1f3a16edc6e2ff
LB-002.1C-A IMPLEMENTATION/CLOSURE COMMIT: 0798b994cc074a4315916a0b45e662d1708c6ab2
PUSHED:                YES
REVIEWED REMOTE STATE AT CLOSURE: HEAD == origin/sergio
DB-GP-001C ORIGINAL FREEZE:       UNCHANGED   (FINAL_DEVELOP_COMMIT historico no se reescribe)
POST-FREEZE REVIEWED TIP:         ADVANCED BY LB-002.1C-A
REASON FOR ADVANCE:    6c120ca desacopla "grupo valido" de "cupo para matricular" (sesiones programables en grupos llenos);
                       LB-002.1C-A corrige su regresion (cupo validado antes de escribir en usp_registrar_estudiante_en_grupo)
GOLDEN PATH CONTRACT CHANGED:          NO   (DB_BASELINE_CONTRACT.md sha 45e48c5a... y manifest de 10 archivos intactos)
FREEZE CONTRACT UNCHANGED:             YES  (DB_BASELINE_CONTRACT.md y manifest sin modificar; el tip revisado avanzo por correccion NON-GOLDEN/interna)
GOLDEN PATH SOURCE CHANGED:            NO
PUBLIC STUDENT-GROUP WIRE/ABI CHANGED IN 1C-A:   NO   (firma, resultset, DBCODEs, RBAC y tablas identicos a 9b2b993)
PUBLIC STUDENT-GROUP BEHAVIOR CORRECTED IN 1C-A: YES  (rechazo por cupo antes de persistir identidad;
                                                       evita estado parcial Usuario/Estudiante)
TRANSACTION OWNERSHIP OF PUBLIC STUDENT ENROLLMENT: NOT CERTIFIED
                                       (OWNERSHIP_STUDENT usa un grupo inexistente: no prueba rollback tras una escritura intermedia;
                                        requiere decision/work item de contrato aparte)
TD-043:                                OPEN   (GLOBAL -Pintegration = NOT_GREEN_TD043)
TABLES CHANGED:                        NO
GOLDEN PATH EFFECTIVE BEHAVIOR:        usp_crear_sesion y usp_generar_sesiones_grupo llaman usp_validar_grupo_exista_por_id_interno;
                                       desde 6c120ca un grupo lleno pero habilitado ya no bloquea (fuente y firma de los SP congelados sin cambio)
GATE ACTUAL:                           TOTAL_EXPECTED=154 (151 + 3 de test_group_capacity_decoupling.sql); las cifras 127/128 del contrato son historicas v1
STUDENT-GROUP CANONICAL COMMAND:       dbo.usp_registrar_estudiante_en_grupo (el legacy ..._usuario_no_existente fue eliminado en daeac11)
CURRENT PUBLIC CONTRACT IS NOT EQUIVALENT TO THE CONTRACT THE HISTORICAL BACKEND EXPECTED: STATUS = DECISION_REQUIRED
CONTRACT DECISION REQUIRED:            YES
DB CONTRACT CHANGE REQUIRED:           TO_BE_DETERMINED_AFTER_BACKEND_AS_IS
DB / BACKEND PRODUCTION CHANGE AUTHORIZED: NO / NO
NEXT AUTHORIZED PHASE:                 LB-002.1C-B1 - BACKEND AS-IS CONTRACT ANALYSIS (registrarEstudianteEnGrupo); no implica cambiar la DB
```

## Revisión post-freeze REC3 (2026-10-29)

- **Objeto:** `schema/stored-procedures/usp_generar_sesiones_grupo.sql`, congelado en DB-GP-001C y ya reemplazado por UTC-D06.
- **Aprobación:** explícita de John Duque (2026-10-29), para este único SP congelado. Los otros congelados que la auditoría señaló (`usp_registrar_asistencias_sesion`, `usp_clasificar_procedencia_sesion` y `usp_crear_sesion_interno`) **no se modifican**.
- **Cambio:**
  - `SET XACT_ABORT ON`;
  - el CATCH pasa de `IF @@TRANCOUNT > 0 ROLLBACK` a `IF XACT_STATE() <> 0 ROLLBACK`.
  - No cambian la firma, el resultset ni las reglas.
- **Manifiesto:** `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256` actualiza solo el hash de ese archivo, de `099a5cf4…` a `ef9de7e9…`. La cadena de reemplazo sigue apuntando al hash DB-GP-001C (`f4c71c7b…`).
- **Prueba:** `test_rec3_falla_intermedia_transaccion.sql`, caso TX-04.
- **Work item:** `docs/work-items/REC3-transacciones/PLAN.md`.

## Revisión post-freeze SES-01 (2026-11-03) — EXCEPCIÓN AUTORIZADA

- **Objeto:** `schema/stored-procedures/usp_registrar_asistencias_sesion.sql` (DB-GP-001C, Golden Path). La revisión REC3 dejó constancia de que este SP **no** se modificaba; SES-01 lo propone de nuevo por una decisión funcional posterior (2026-11-02: cierre estricto a la hora de fin).
- **Aprobación:** excepción de congelamiento **autorizada expresamente por el responsable funcional del proyecto** (instrucción del 2026-11-03, «Finalización integral de SES-01 a SES-05»). La autorización cubre desarrollar, probar y proponer el cambio; la **revisión formal del owner DB (John Duque)** se solicita en el PR y es requisito para fusionar y para aplicarlo en bases compartidas, que se hace solo con el mecanismo oficial de despliegue.
- **Cambio:**
  - PASO 4.0: dentro de la transacción (propia o savepoint) llama a `usp_validar_sesion_ventana_registro_interno` antes de escribir;
  - PASO 4.2: repite la validación antes del `COMMIT`;
  - fuera de ventana devuelve `SES_007` / `SES_008` / `SES_009` y no escribe.
  - No cambian la firma, el resultset, la prioridad de las validaciones previas ni el patrón savepoint/`XACT_STATE()` (sin `XACT_ABORT ON`, ver REC3).
- **Manifiesto:** `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256` agrega la supersesión de ese archivo, de `a0372fd6…` (DB-GP-001C) a `7217604b…`; `scripts/freeze-manifest.ps1` lo incluye en `$postFreezeSuperseded`.
- **Prueba:** `test/test_ses01_ventana_asistencia.sql` (12 IDs `SES01_*`).
- **Work item:** `docs/work-items/SES-01-cierre-estricto-asistencia/PLAN.md`.

## CULM-001 D.4 — admisión de estudiantes por el administrador (HU156) (2026-11-07)

- **Objetos nuevos:** `usp_admitir_estudiante`, `usp_consultar_programas_institucion_paginado`, mensajes `ADS_001`..`ADS_006`, parámetros `IDENTIDAD/PERFILES_CORRECCION_ESTUDIANTE` y `_DECANO`, permisos `rol_asistencias_runtime_culm001_d4.sql` y la migración `23_culm001_d4_admision_estudiantes`. Ningún archivo congelado cambia; las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Cambio de comportamiento:** `usp_corregir_identidad_usuario` lee los perfiles permitidos de los parámetros; el `ADMINISTRADOR` ahora corrige estudiantes con `EstudiantePrograma` en un programa de su institución (antes solo el `COORDINADOR` del programa). Coordinador y decano conservan su regla.
- **Desviación del contrato:** el vínculo con el programa se inserta en `usp_admitir_estudiante` y no con `usp_registrar_estudiante_en_programa_interno` (resuelve la institución desde `uv_estudiante`, que exige un programa previo); `Programa` no tiene columna `codigo`, por eso la consulta de programas no la devuelve.
- **Pruebas:** `test/test_culm001_d4_admision.sql` (D4-01..D4-11) y `test/test_culm001_d4.ps1` (D4-12 up→down→up).
## CULM-001 D.1 — plazo de excusas (HU026B) (2026-11-07)

- **Objetos nuevos:** `ufn_calcular_fecha_limite_justificacion`, `usp_internal_validar_plazo_justificacion`, `uv_sesion_estudiante_reclamo`, `usp_consultar_sesiones_materia_estudiante` y la migración `20_culm001_d1_plazo_justificacion`. Ningún archivo congelado cambia (`uv_sesion` no se toca, DEC-044 (2)); las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Radicación:** `usp_radicar_solicitud_revision_asistencia` (v1) y `_v2` rechazan con `REV_020` cuando `SYSUTCDATETIME() >= límite` y con `REV_025` cuando faltan `ASISTENCIA/DIAS_LIMITE_JUSTIFICACION` o `TIEMPO/ZONA_HORARIA_SQLSERVER`. El límite es la medianoche local del día `fecha local de fin + N + 1`. En la v2 el plazo se valida **después** de la reejecución idempotente por correlación (un reintento legítimo tras el vencimiento sigue devolviendo el éxito original) y antes de cualquier escritura.
- **Fecha de radicación (F-EST-S16):** `SolicitudRevisionAsistencia.fecha` pasa de `CAST(CURRENT_TIMESTAMP AS DATE)` (fecha del servidor, UTC) a la **fecha local** (`TIEMPO/ZONA_HORARIA_SQLSERVER`). Las filas anteriores conservan su fecha (sin migración de datos).
- **Cambio de comportamiento de lectura (DEC-022 §3):** la lista de sesiones de la materia del estudiante solo devuelve grupos con la matrícula `MATRICULA/ESTADO_INSCRITA`; con `I`, `CI`, `CVP` o `F` devuelve 0 filas.
- **LB-004D:** cambian `usp_radicar_solicitud_revision_asistencia_v2.sql`, `test_lb004d_support_binding.sql` (la fixture usa «ayer» en lugar de una fecha fija ya vencida) y `test_lb004d_concurrency.ps1` (crea y elimina una sesión reciente propia); sus líneas del manifiesto se regeneran en el mismo commit (DEC-044 (11)).
- **Pruebas:** `test/test_culm001_d1_plazo_justificacion.sql` (D1-01…D1-10, D1-12), `test/test_culm001_d1.ps1` (D1-11 up→down→up y D-RB-01).

## CULM-001 D.2 — varios soportes por reclamo, categoría persistida y soporte obligatorio (HU014/HU015) (2026-11-08)

- **Objetos nuevos:** `uv_soporte_reclamo`, `usp_internal_radicar_solicitud_revision` (sin `GRANT`), `usp_radicar_solicitud_revision_asistencia_v3`, `usp_consultar_configuracion_reclamos` y la migración `21_culm001_d2_soportes_categoria` (semilla `52_culm001_d2_parametros_mensajes.sql`). Ningún archivo del Golden Path congelado cambia; las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Tablas:** `SolicitudRevisionAsistencia.categoriaJustificacion` (FK e índice, sin backfill, TD-060), `CategoriaJustificacion.requiereSoporte` (MED, ACA y LAB) y, en `ArchivoSoporte`, `UX_ArchivoSoporte_Solicitud` (único filtrado) se reemplaza por `IX_ArchivoSoporte_Solicitud` (no único; [SUPUESTO-D-02]/DEC-042; cierra TD-059 —con el índice filtrado y la FK habilitada, cualquier `DELETE` de una solicitud fallaba con Msg 8624—, verificado por D2-14).
- **Radicación:** `usp_radicar_solicitud_revision_asistencia_v2` conserva firma y resultset de 4 columnas y delega en el interno; guarda la categoría (`REV_021` si no existe) y exige soporte según la categoría (`REV_022`). `_v3` recibe `@idsArchivoSoporte` (arreglo JSON, hasta `ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO`, `REV_023`/`REV_024`) y devuelve además `idSolicitudRevision` y `totalSoportes`. La reejecución idempotente por correlación precede al plazo; el plazo (D.1) ya vive en el interno.
- **Lecturas:** R2, detalle del docente y lista del estudiante agregan al final `codigoCategoria`, `nombreCategoria` y `totalSoportes` (R2) o `soportesJson` (detalle y lista); las columnas de soporte siguen siendo las del primer soporte. TD-061: `ARCHIVO/ESTADO_BORRADOR` y `ARCHIVO/ESTADO_ADJUNTO` reemplazan los literales `DRAFT`/`ATTACHED` en la descarga autorizada, R2 y el interno.
- **LB-004D:** cambian `ArchivoSoporte.sql`, `usp_radicar_solicitud_revision_asistencia_v2.sql`, `usp_consultar_archivo_soporte_autorizado.sql`, `usp_consultar_solicitudes_revision_docente.sql`, `test_lb004d_support_binding.sql` y `test_lb004d_concurrency.ps1`; sus líneas se regeneran en el mismo commit que cambia cada archivo (DEC-044 (11)).
- **Rollback:** el `down` de la 21 aborta con `THROW 50021` sin `CONFIRMAR_COLAPSO_SOPORTES = 1` si hay solicitudes con más de un soporte, archiva categorías y soportes colapsados en `zz_archivo_*` y deja v2 en el texto de D.1; el `down` de la 20 aborta con `50020` mientras exista el interno (D-RB-01).
- **Pruebas:** `test/test_culm001_d2_soportes_categoria.sql` (D2-01…D2-10, D2-12, D2-14…D2-16), `test/test_culm001_d2.ps1` (D2-13 up→down→up, down sin confirmación, D-RB-01), D2-11 en `test/test_lb004d_concurrency.ps1`.

## CULM-001 D.9-a — hallazgos medios y bajos de BD (2026-11-08)

- **Objetos nuevos:** `usp_consultar_periodos_academicos_paginado` (administrador; `esVigente` con la fecha local), `usp_consultar_grupo_facultad_detalle` (decano; `SEC_002` si el grupo no existe o es ajeno), `usp_validar_acceso_reporte_grupo` (ámbito del reporte Excel; `SEC_002`), mensajes `DEC_020`, `NTF_020` y `NTF_021`, permisos `rol_asistencias_runtime_culm001_d9.sql` y la migración `28_culm001_d9_hallazgos` (semilla `59_culm001_d9_mensajes.sql`). Ningún archivo congelado ni de LB-004D cambia; las fuentes nuevas se registran como `WORK_ITEM` en `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256`.
- **Objetos modificados:** `usp_crear_decano` (`DEC_020` antes de abrir la transacción; parámetro `@idTipoIdIdentificacion` al final de la firma, con el mismo nombre que usará D.5), `usp_reintentar_notificacion_saliente_interno` (`NTF_020`), `usp_consultar_plantilla_notificacion_activa` (`@validarExistencia`, `NTF_021`), `usp_crear_periodo_academico` (columna `idPeriodo` al final), `usp_consultar_sesiones_facultad_paginado` (`@idGrupo`, `SEC_002`) y `usp_validar_cruce_horario_estudiante_interno` (solo `MATRICULA/ESTADO_INSCRITA`, R-8 de A).
- **Desviaciones del contrato:** (1) `NTF_021` es opt-in (`@validarExistencia = 1`): el despachador de correos usa el mismo SP con tipos sin fila en BD y debe seguir recibiendo 0 filas para usar su plantilla por defecto; (2) el reporte Excel no tenía SP, por eso `usp_validar_acceso_reporte_grupo` es nuevo; (3) `usp_consultar_periodos_academicos_paginado` es nuevo porque el listado del coordinador es un HQL sobre `uv_periodo_academico`, no un SP; (4) el `down` de la 28 no reescribe `usp_crear_decano` si contiene el texto de D.5 (`TIPO_IDENTIFICACION_DEFECTO`).
- **Datos:** `schema/seed/14_grupos_sesiones.sql` siembra la franja `LU 08:00-10:00` del grupo sembrado (coherente con SES-01/SES-02) y `test/fixtures/culm1_segundo_ambito.sql` calcula el día de su franja desde la sesión vencida. El fixture de datos limpios (`seed-clean-data.ps1`) vive en Infra y no se tocó (D.9-d).
- **Pruebas:** `test/test_culm001_d9_hallazgos.sql` (D9-DEC-01…05, D9-NTF-01/02, D9-MSG-01, D9-PER-01/02, D9-HOR-01, D9-TRX-01…03, D9-CRU-01), `test/test_culm001_d9.ps1` (migración 28 up→down→up y D-RB-03; el contrato la ubicaba en `test_culm001_d_rollback.sql`, compartido con D.5). `test_contract_closure.sql` excluye de la regla canónica a los dos SP de lectura nuevos y a `usp_validar_acceso_reporte_grupo` (fija `SESSION_CONTEXT`) y admite la columna `idPeriodo`.

## CULM-001 C.1 — cancelacion por inasistencia (HU026C)

- `EstudianteGrupo` pasa a `CI` unicamente al aprobar una `RevisionCancelacion` (`usp_resolver_revision_cancelacion`); el cierre masivo (`usp_ejecutar_cierre_masivo_periodo`) ya no cancela por conteo de faltas.
- Cierre masivo con el motor habilitado y umbrales validos: responde `RCN_012` (una sola fila) si hay revisiones que esperan al docente o al resolutor, o perdidas por horas sin revision; no crea revisiones ni evalua alertas (lo hace el backend antes). Con el motor apagado o umbrales invalidos no bloquea y `AuditoriaEvento` registra `motorHabilitado`, `umbralesValidos`, `perdidasSinRevision` y `revisionesPendientes`.
- Unicidad: una `AlertaInasistencia` por (matricula, tipo) y una `RevisionCancelacion` por matricula.
- Escalamiento: el resolutor es el coordinador activo del programa del estudiante (excluido quien propuso); sin coordinador, el decano de la facultad (`ufn_revision_cancelacion_resolutores`).
- `Grupo.cantidadEstudiantesCancelaronAutomaticamente` significa "matriculas en CI al cierre".
- Migracion 19 (`up|down`), semillas 40/41 y permisos `rol_asistencias_runtime_culm001_c.sql`.
## CULM-001 D.8 — comparativas, tendencia y consolidado por horas (HU061/HU103/HU134/HU139) (2026-11-08)

- **Objetos que cambian (sin objetos nuevos):** `usp_consultar_comparativa_facultades`, `usp_consultar_comparativa_programas_facultad`, `usp_consultar_tendencia_ausentismo` y `usp_consultar_consolidado_asistencia_grupos_paginado`, más la migración `27_culm001_d8_kpis_horas` (el `down` restaura el texto de B2 + B.2 y el `up` es idempotente). No se tocan archivos congelados ni de LB-004D.
- **Fórmula (DEC-012, DEC-024):** el ausentismo pasa de sesiones a horas. Comparativas: `ROUND(100 · Σ horasFalta / Σ horasDictadas, 2)` (`NULL` si Σ `horasDictadas` = 0); la facultad cuenta cada matrícula una sola vez. Tendencia: `ROUND(100 · Σ horasFalta / Σ (horasSesion × matrículas activas de la sesión), 2)` por semana o mes local; las sesiones canceladas no cuentan. Consolidado: con `D = horasDictadas × activos del programa en el grupo`, `porcentajeAsistencia`, `porcentajeInasistencia` y `porcentajeExcusa` son `ROUND(100 · horas / D, 2)` y `porcentajeSinRegistro = MAX(0, 100 − las tres)`; si la suma de los tres redondeos supera 100 el exceso se resta del mayor (empate: asistencia, inasistencia, excusa) y los cuatro suman `100.00` (R-1); con `D = 0` los cuatro son `0`.
- **Columnas nuevas, siempre al final (unidad):** comparativas `horasDictadas DECIMAL(12,2)` y `horasFalta DECIMAL(12,2)` (horas, suma sobre las matrículas activas); tendencia `horasDictadasEstudiante DECIMAL(14,2)` y `horasFalta DECIMAL(14,2)` (horas-estudiante); consolidado, después de `totalRegistros`, `horasDictadas DECIMAL(12,2)` (horas dictadas del grupo, por estudiante, no multiplicadas por los activos), `porcentajeExcusa DECIMAL(5,2)` y `porcentajeSinRegistro DECIMAL(5,2)` (porcentaje 0–100). Las columnas existentes conservan nombre, tipo y posición; `sesionesEjecutadas`, `faltasSinJustaCausa`, `asistencias` y `excusas` siguen en sesiones o tomas.
- **Cambio de comportamiento:** los números cambian cuando las sesiones tienen duraciones distintas o varias tomas; con una toma y sesiones de igual duración coinciden con la fórmula anterior (D8-04). Los cuatro SP leen el estado de matrícula de `MATRICULA/ESTADO_INSCRITA` (sin el literal `A`, OBS-8).
- **Corrección sobre el texto de B2:** el consolidado declaraba `PRIMARY KEY (id)` en la variable de grupos del ámbito y fallaba (Msg 2627) con un grupo de dos programas visible para el decano o el administrador; la clave pasa a `(id, idPrograma)`, el grano que el contrato de B2 ya fijaba.
- **Pruebas:** `test/test_culm001_d8_kpis_horas.sql` (D8-01…D8-07 y D8-09), `test/test_culm001_d8.ps1` (D8-08 up→down→up). Cambian por D.8 §9.2: las listas de columnas de `test_usp_consultar_comparativa_facultades`, `test_usp_consultar_comparativa_programas_facultad`, `test_usp_consultar_tendencia_ausentismo` y `test_consolidado_auditoria_catalogos`, y el bloque «diferidos» de `test_culm001_b2_horas` (la equivalencia «2 tomas = 1 toma» ya no aplica con horas).

## CULM-001 / DEC-064 — sesiones manuales: aviso y cancelación por el coordinador (HU047) (2026-11-09)

- **Regla (DEC-064):** la sesión que el docente crea manualmente (fuera de la precarga) se crea, se avisa de inmediato a los estudiantes activos del grupo y al coordinador del programa, y el coordinador puede cancelarla. Una sesión es *manual* si `Sesion.procedenciaTemporal` es NULL (creada por v1) o `UTC_V2` (creada por v2) (`uv_sesion_manual`); la precarga/generador marca `UTC_GENERADOR` y la clasificación de históricos `UTC_OWNER` (no manuales). Limitaciones: NULL incluye filas históricas previas a UTC-D06 y una sesión generada que el docente edita por la vía v2 pasa a `UTC_V2`. Ningún archivo congelado ni de LB-004D cambia (`usp_crear_sesion`, `usp_cancelar_sesion` y sus firmas quedan intactos).
- **Objetos nuevos:** tabla `MotivoCancelacionSesion` + `uv_motivo_cancelacion_sesion` (5 motivos sembrados), `uv_sesion_manual`, `usp_consultar_destinatarios_sesion_manual(@idSesion,@idCorrelacion,@idUsuarioEjecutor)` (docente titular; filas `ESTUDIANTE` y `COORDINADOR`, un coordinador de dos programas es una fila), `usp_consultar_motivos_cancelacion_sesion(@idUsuarioEjecutor,@idCorrelacion)` (coordinador) y `usp_cancelar_sesion_coordinador(@idSesion,@codigoMotivo,@observacion,@idCorrelacion,@idUsuarioEjecutor)` (misma tupla que `usp_cancelar_sesion`). Ámbito del coordinador: coordina al menos uno de los programas del grupo (`SEC_002` si no). Mensajes `SES_018` (no manual), `SES_019` (motivo inválido), `SES_020` (éxito), `SES_021` (observación > `SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA` = 250); reutiliza `SES_011/012/016`.
- **Notificaciones:** plantillas `SESION_MANUAL_CREADA_ESTUDIANTE` y `SESION_MANUAL_CREADA_COORDINADOR` (semilla `60_sesiones_manuales_plantillas.sql`); el outbox lo escribe el backend.
- **Migración y permisos:** `29_sesiones_manuales_notificacion_up|down.sql` (idempotente), `rol_asistencias_runtime_sesiones_manuales.sql`.
- **Pruebas:** `test/test_sesiones_manuales_notificacion.sql` (SMN-00…07), `test/test_sesiones_manuales_notificacion.ps1` (migración 29 up→down→up). `test_contract_closure.sql` admite los 3 SP nuevos como no canónicos y `test_public_objects.sql` verifica sus permisos.

## HU018 / HU019 — plan de estudios por semestres y horas programadas del estudiante (2026-11-10)

- **Regla (decisión de John, 2026-11-10):** el estudiante consulta la estructura curricular de sus programas por semestres (HU018) y, en cada materia, compara las horas a las que asistió con las dictadas y con las programadas del grupo (HU019). La aplicación no maneja notas, así que la barra de HU019 es por horas y no por créditos aprobados. Privacidad: los dos SP resuelven al estudiante desde el ejecutor y no reciben ningún identificador de otro estudiante.
- **Objetos nuevos:** `usp_consultar_plan_estudio_estudiante(@idUsuarioEjecutor,@idCorrelacion)` (18 columnas; planes ACTIVOS de los programas del estudiante, una fila por semestre y asignatura con vínculo activo y asignatura activa; un semestre sin asignaturas sale en una fila sin asignatura; `cursando` con la matrícula del parámetro `MATRICULA/ESTADO_INSCRITA`) y `usp_consultar_horas_programadas_estudiante(@idUsuarioEjecutor,@idCorrelacion)` (4 columnas; una fila por matrícula inscrita con las sesiones y horas de `uv_cumplimiento_sesion_grupo`, que excluye las canceladas). Los dos son `READ_QUERY_RESULTSET`, `NON_GOLDEN_PATH_EXTENSION` y responden `VAL_001` (THROW 51000) con el ejecutor nulo; quien no es estudiante obtiene 0 filas.
- **Objetos que cambian:** ninguno. `usp_consultar_resumen_asistencia_estudiante` y `usp_consultar_materias_estudiante` no se tocan; el backend une las horas programadas por `idGrupo`.
- **Migración y permisos:** `33_hu018_hu019_plan_horas_estudiante_up|down.sql` (idempotente; el `down` solo elimina los dos SP), `rol_asistencias_runtime_hu018_hu019.sql`.
- **Pruebas:** `test/test_hu018_hu019_plan_horas_estudiante.sql` (HU018_PLAN_ESTRUCTURA_ORDEN, HU018_PLAN_EXCLUSIONES, HU018_PLAN_CURSANDO, HU018_PLAN_PRIVACIDAD, HU018_PLAN_COLUMNAS, HU019_HORAS_PROGRAMADAS y HU019_HORAS_VALIDACIONES), `test/test_hu018_hu019.ps1` (migración 33 up→down→up). `test_contract_closure.sql` admite los 2 SP nuevos como no canónicos y `test_public_objects.sql` verifica sus permisos (HU018_HU019_SEG_01).

## Validaciones compartidas de sesión — sin cambio funcional (2026-11-10)

- **Motivo:** el análisis de SonarCloud de `develop` falló por código duplicado (3,28 % sobre un límite de 3 %). Dos bloques de validación estaban copiados en varios procedimientos de sesiones.
- **Objeto nuevo:** `usp_validar_docente_titular_sesion_interno(@idSesion,@idUsuarioEjecutor,@idCorrelacion, salidas canónicas)`: correlación presente, ejecutor y sesión obligatorios (`GEN_002`), RBAC `DOCENTE` y titularidad `SESION`. No escribe, no abre transacciones y no lanza. No se concede al rol runtime (encadenamiento de propiedad).
- **Objetos que cambian (solo el cuerpo):** `usp_consultar_destinatarios_sesion_cancelada` y `usp_consultar_destinatarios_sesion_manual` delegan su validación en el interno nuevo y siguen lanzando `THROW 51000` con el mensaje técnico. `usp_cancelar_sesion_coordinador` delega sus pasos 1 a 4 en `usp_validar_coordinador_sesion_interno` (migración 30).
- **Contrato:** no cambian firmas, columnas, orden, mensajes, códigos ni permisos.
- **Migración:** `34_deduplicar_validaciones_sesion_up|down.sql` (idempotente; el `down` restaura los tres textos previos y elimina el interno).
- **Pruebas:** `test/test_dedup_validaciones_sesion.ps1` (`DVS_MIG_UP_DOWN_UP`, migración 34 up→down→up). Las pruebas funcionales existentes de los tres procedimientos (`test_sesiones_manuales_notificacion.sql`, B.1 y `test_mrm_solicitud_sesion.sql`) siguen pasando sin cambios.

## HU177 — retiro del flujo propio de recuperación de contraseña (2026-11-11)

- **Regla (decisión de John, 2026-11-11):** recuperar la contraseña es del servicio de seguridad de terceros (Security Baseline / Keycloak), no de esta aplicación. HU177 queda pendiente de terceros.
- **Qué se retira:** el flujo propio que estuvo unas horas en `develop` (migración 35): tabla `TokenRecuperacionClave` y su FK, los SP `usp_consultar_solicitud_recuperacion_clave`, `usp_emitir_token_recuperacion_clave`, `usp_consultar_token_recuperacion_clave` y `usp_consumir_token_recuperacion_clave`, los mensajes `RCL_001`…`RCL_003`, los parámetros `RECUPERACION_CLAVE/*`, la plantilla de correo `RECUPERACION_CLAVE` y sus permisos. El repositorio vuelve al estado anterior a HU177.
- **Migración:** `36_hu177_retiro_recuperacion_clave_up|down.sql`. El `up` elimina esos objetos y semillas solo si existen (ambientes donde se aplicó la 35); el `down` no tiene efecto. El número 35 queda sin usar.
- **Pruebas:** `test/test_hu177_retiro.ps1` (`HU177_RETIRO_MIG`).
