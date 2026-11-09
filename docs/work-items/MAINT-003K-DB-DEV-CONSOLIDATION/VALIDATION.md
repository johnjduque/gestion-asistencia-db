---
status: LOCAL_PRIMARY_DB_CERTIFIED_REMOTE_CI_PASS
work_item: MAINT-003K-DB-DEV-CONSOLIDATION
date: 2026-10-10
---

# MAINT-003K-DB-DEV-CONSOLIDATION — Validacion (evidencia real, contenedor de desarrollo)

Estados independientes (no se declara ninguno sin evidencia):

| Estado | Valor | Evidencia |
|---|---|---|
| `DEV_DB_CONSOLIDATED` | **PASS** | Secciones históricas 3-6 más la certificación final sobre `sql_server_asistencias` en sección 12. |
| `DB_PR_READY` | **PASS local + CI remoto** | Gate real del nuevo HEAD aprobado en la DB principal y por GitHub Actions/SonarCloud. |
| `BACKEND_LOCAL_GREEN` / `BACKEND_CI_GREEN` | ver el work item backend | `docs/work-items/MAINT-003K-backend-only-release-gate/VALIDATION.md` |

## 1. Inventario previo (solo lectura)

| Contenedor | Imagen | Puerto | Volumen | Uso |
|---|---|---|---|---|
| `sql_server_asistencias` | mssql/server:2022 (Developer) | 1433 | `sql_server_asistencias_data` | **principal**: el backend lee `jdbc:sqlserver://localhost:1433;databaseName=gestionasistenciadb` (`.env`) |
| `maint003k_cert_20261011` | mssql/server:2022 | ninguno | ninguno | **retirado** tras inspección; no fue usado para certificar el nuevo HEAD |
| `utc_d06_sqltest` | mssql/server:2022 | 127.0.0.1:14333 | ninguno (efimero) | temporal D06; unico consumidor: un backend huerfano de una sesion previa (PID 23100, puerto 18080, 10 conexiones) |
| (segundo temporal) | — | — | — | **no existia como contenedor**: el segundo artefacto temporal era la base `gestionasistenciadb_fase1` dentro del contenedor principal (restaurada de `fase1_backend_2026-10-09.bak`) |

Estado de la DB principal antes de reconstruir: 35 tablas, 55 vistas, 59 SP, 52 indices, **0 roles**, 0 triggers; sin D06 ni CC-003G-01 (tenia versiones previas de
`usp_sincronizar_usuario` y `usp_registrar_o_actualizar_plan_estudio`). Datos: 54 usuarios (47 `*.invalid`, 6 del seed 12, 1 cuenta dev), 129 eventos de auditoria,
3 sesiones, 9 asistencias. Todo sintetico; destino verificado como exclusivamente local (contenedor en la maquina del desarrollador, Developer Edition,
sin `OPERACION/AMBIENTE` productivo).

**Contenido fuera de Git:** comparados los 169 objetos de `utc_d06_sqltest` y los 164 de `gestionasistenciadb_fase1` con la DB principal desplegada desde Git:
0 objetos ausentes y 0 definiciones de modulo distintas, salvo `uv_estudiante_programa` (correccion de esta rama). Solo difieren **datos** de prueba.

## 2. Respaldo y prueba de restauracion (rollback)

| Respaldo | Verificacion |
|---|---|
| `gestionasistenciadb_pre_maint003k_20261010_052904.bak` (3 039 232 B, sha256 `ae6fe903…`) | `BACKUP ... WITH CHECKSUM`; `RESTORE VERIFYONLY ... WITH CHECKSUM` valido; **restauracion real** a `gestionasistenciadb_restoretest` (59 SP, 55 vistas, 54 usuarios, 3 sesiones, 129 auditoria = identico al origen) + `DBCC CHECKDB` sin errores; base de prueba eliminada |
| `gestionasistenciadb_fase1_pre_maint003k_20261010_052904.bak` (sha256 `35012149…`) | `BACKUP WITH CHECKSUM` + `RESTORE VERIFYONLY` valido |
| `utc_d06_sqltest_final_20261010_052904.bak` (sha256 `38048ffa…`) | `BACKUP WITH CHECKSUM` + `RESTORE VERIFYONLY` valido |

Copias: dentro del contenedor (`/var/opt/mssql/backup`) y en el host `C:\Users\josev\AsistenciasUCO\db-backups\` (fuera de los repos).
Rollback de la DB: `RESTORE DATABASE gestionasistenciadb FROM DISK='/var/opt/mssql/backup/gestionasistenciadb_pre_maint003k_20261010_052904.bak' WITH REPLACE`
(probado como restauracion a otro nombre). Rollback de codigo: `git revert` de los commits de la rama; produccion no se toca.
Tambien se probo una **restauracion del backup pre-D06 como DB temporal** para comprobar que el backend con `app.sesiones.v2.enabled=true` aborta el arranque
(GATE-02 del backend) y se elimino despues.

## 3. Reconstruccion de la DB principal desde Git

`DROP DATABASE gestionasistenciadb` (modo single-user, con respaldo verificado) y despliegue con `deploy_schema.ps1 -ContainerName sql_server_asistencias`
(exit 0, 0 mensajes `Msg` en el log) sobre `db452bb`. Instalado: 36 tablas, 56 vistas, 64 procedimientos, 54 indices, 1 trigger, 2 roles
(`rol_asistencias_runtime`, `rol_asistencias_clasificador_temporal`), catalogos de 67 mensajes y 24 parametros, columna `Sesion.procedenciaTemporal`
con `CK_Sesion_ProcedenciaTemporal` confiable, `uv_sesion_v2`, SP v1/v2 de sesiones, `usp_clasificar_procedencia_sesion`, `usp_sincronizar_usuario`,
`usp_registrar_o_actualizar_plan_estudio`.

### Idempotencia (huellas SHA-256 de definiciones, columnas, indices, permisos y catalogos + conteos por tabla)

| Despliegue | FP_modules | FP_columns | FP_indexes | FP_permissions | FP_catalogs | filas |
|---|---|---|---|---|---|---|
| 1 (limpio) | `4B4EEB26…` | `FAA74F44…` | `42DE4D5B…` | `EF060018…` | `13903A26…` | base |
| 2 | idem | idem | idem | idem | idem | — |
| 3 | idem | idem | idem | idem | idem | **identicas** |
| tras la correccion de `uv_estudiante_programa` | `FAD627D2…` (cambia solo por la vista corregida) | idem | idem | idem | idem | — |
| re-despliegue sobre el estado final | `FAD627D2…` | idem | idem | idem | idem | **identicas** (incluso tras `test_summary.ps1`: sin residuos) |

## 4. Gate SQL (`test_summary.ps1`) contra la DB principal

| Ejecucion | Esperados | Ejecutadas | PASS | FAILED | SKIPPED | Faltantes criticos |
|---|---|---|---|---|---|---|
| Base desplegada (sin fixtures), `db452bb` | 216 | 219 | 218 | 0 | 1 (`XACT_STATE_MINUS_ONE_RUNTIME`, permitido) | 0 |
| Con fixtures (primer intento) | 216 | 219 | 217 | **1** | 1 | 1 |
| Con fixtures, tras corregir el fixture | 216 | 219 | 218 | 0 | 1 | 0 |
| Con fixtures + `uv_estudiante_programa` corregida (`9f3889f`) | **217** | **220** | **219** | 0 | 1 | 0 |
| Estado final (tras ITs/E2E del backend) | 217 | 220 | 219 | 0 | 1 | 0 |

El unico skip es el heredado `XACT_STATE_MINUS_ONE_RUNTIME` (`UNAUTHORIZED_SKIPS=0`). Incluye: `UTC_D06_SEED_UTC`, `UTC_D06_RUNTIME_PERMISSIONS`,
`CC003G01_RUNTIME_*` (login SQL real de minimo privilegio, no `sa`), `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED`, `UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES`.

## 5. Defectos encontrados y corregidos en esta rama

1. **Seed 14 con fechas ambiguas** (`2026-08-17 08:00` sin procedencia): ahora `13:00:00.0000000Z`/`15:00:00.0000000Z` con `UTC_V2`; el test que afirmaba el seed antiguo
   (`UTC_D06_LEGACY_ROWS_NULL`) se reemplazo por `UTC_D06_SEED_UTC` (los historicos NULL siguen cubiertos por otros ids).
2. **`uv_estudiante_programa` duplicaba filas** para estudiantes multigrupo (hallazgo del IT `EstudianteProgramaJpaParityIT` con fixtures; RED -> GREEN con
   `UV_ESTUDIANTE_PROGRAMA_NO_DUPLICATES`).
3. **Falso positivo de `AULA_ACTIVE_SQL_REFERENCES_ZERO`**: el nombre de fixture "Paula" contiene la subcadena `aula` que busca el gate; renombrado.

## 6. Datos nuevos para pruebas (fixtures `test/fixtures/dev`)

Cargados con `deploy_dev_fixtures.ps1` (limpieza -> carga -> validacion; ejecutado dos veces, idempotente): **5 003 usuarios** (5 000 estudiantes + 3 docentes fixture),
5 000 estudiantes, 3 docentes, 3 grupos (`FIX-PAG-300/1000/5000`, un docente titular por grupo), **6 300 matriculas** (estudiantes 1..300 en 3 grupos, 301..1000 en 2),
**12 sesiones** (4 por grupo, UTC `DATETIME2(7)` `UTC_V2`, la 1 con `.1234567`/`.7654321`), **6 348 asistencias** y **6 348 detalles** (solo matriculas activas;
grupo 300: sesiones 1-3, otros: sesion 1). Estados: A 92 %, I/CVP/CI/F 2 % c/u; ~1 % de usuarios inactivos; parejas de estudiantes con el mismo nombre completo.
Validado: orden estable, paginas concatenadas == lista completa, primera/ultima/fuera de rango/vacio, filtros, duplicados multigrupo, integridad referencial
(`DBCC CHECKCONSTRAINTS`). No se crearon cuentas de Keycloak para los fixtures.

Estado final de la DB principal (incluye datos de los ITs de Java): Usuario 5 011, Estudiante 5 003, Docente 5, Grupo 5, EstudianteGrupo 6 302, Sesion 15
(14 `UTC_V2` + 1 historica NULL creada por el fixture Java `IT-MAINT003G` via SP v1), Asistencia/DetalleAsistencia 6 350, AuditoriaEvento 64.

## 7. Retiro de temporales

Sin consumidores restantes tras detener el backend huerfano PID 23100 (jar del proyecto con 10 conexiones al temporal; era un residuo de un E2E previo):
`docker stop` + `docker rm utc_d06_sqltest` (sin volumenes), `DROP DATABASE gestionasistenciadb_fase1` (respaldada). Intactos: `sql_server_asistencias`,
MinIO, ClamAV, Keycloak y su PostgreSQL, y la pila de observabilidad. Se restauro desde el respaldo la cuenta dev no versionada
(`dbo.Usuario`/`dbo.Estudiante` con id `16F080CD-…`) para no romper su vinculo con Keycloak.

## 8. NOT_RUN / limitaciones

- CI remoto del nuevo HEAD (`DB Quality Gate CI/CD`) y SonarCloud: **PASS** en el run 24 (`38125569939`); CodeQL no está configurado en este workflow.
- Despliegue en staging/institucional y aprobacion del owner DB: **NOT_RUN** (decision humana).
- `XACT_STATE_MINUS_ONE_RUNTIME` sigue siendo skip permitido.

## 9. MAINT-003K-Sonar follow-up (SHA auditado `af37ccc8d30100fbffda7ab3a4034734153374b3`)

| Comprobacion | Resultado | Evidencia |
|---|---|---|
| SonarCloud final del SHA auditado | **PASS**: 0,0 % de duplicación en código nuevo; 0 issues nuevos | Evidencia aportada para PR #36 y asociada a `af37ccc8...` |
| Matriz local de candidatos | **COMPLETADA** | El bloque comun de procedencia/correlacion/RBAC/fechas fue extraido; los wrappers y proveedores quedaron sin cambios |
| Issue `catch {}` vacio | **CORREGIDO EN FUENTE** | `test_summary.ps1`: ambas limpiezas registran errores y siempre intentan la limpieza SQL |
| Manifiesto post-freeze | **PASS local** | `scripts/freeze-manifest.ps1 -Mode Verify` => `FREEZE_MANIFEST_OK`, 11 objetos work-item |
| Parseo PowerShell | **PASS local** | `test_summary.ps1` => `POWERSHELL_PARSE_OK` |
| SQL Server 2022 limpio + redeploy + suite del SHA auditado | **PASS histórico** | `TOTAL_EXECUTED=225`, `PASSED=224`, `FAILED=0`, `SKIPPED=1`; único skip `XACT_STATE_MINUS_ONE_RUNTIME` |
| Manifiesto post-freeze del SHA auditado | **PASS histórico** | `FREEZE_MANIFEST_OK`; 11 objetos post-freeze |
| SQL Server principal + suite del nuevo HEAD | **PASS** | `sql_server_asistencias/gestionasistenciadb`, gate final registrado en sección 12 |
| SonarCloud, DB CI y GitHub Actions del nuevo HEAD | **PASS** | Run 23 (`38125366104`) sobre `d9741b12b68f3737726e3d1ecd7f05c211a8b543`: despliegue, `test_summary.ps1`, SonarCloud y post-checkout exitosos |

## 10. Regresión de prioridad de errores

La revisión de `af37ccc8^` contra `af37ccc8` mostró que la extracción de fechas al helper común adelantó `SES_004`
respecto de `ERR_GRUPO_NO_EXISTE` y `SES_001`. Se restauró el orden mediante `@faseValidacion`: fase 0 para
procedencia/correlación/RBAC, validación de grupo o sesión y titularidad, y fase 2 para fechas. Las pruebas
`SESSION_ERROR_PRIORITY_CREATE_GROUP_BEFORE_DATES` y `SESSION_ERROR_PRIORITY_UPDATE_SESSION_BEFORE_DATES` verifican
las cuatro columnas contractuales y que no cambie el conteo de `uv_sesion`. Ambos pasaron en la ejecución final sobre
la DB principal.

## 11. Estado de integración

La aprobación humana específica del responsable DB y de seguridad no está registrada en este checkout. El merge a
`develop`, la eliminación de la rama remota y cualquier despliegue siguen deliberadamente sin ejecutarse por instrucción
del usuario.

## 12. Certificación final sobre la DB principal

El 2026-10-11 se verificó `sql_server_asistencias` como SQL Server 2022 Developer y se aplicaron solo los tres
procedimientos modificados. El backup previo fue `C:\Users\josev\AsistenciasUCO\db-backups\maint003k_pre_priority_20261011.bak`
(17.952.768 bytes, SHA-256 `e344ef3d644b860666d4686d263e878b0a3cdfd11ca23f026b9ad302a9f432e1`).

Resultado real del gate: `TOTAL_EXPECTED=224`, `TOTAL_EXECUTED=227`, `PASSED=226`, `FAILED=0`, `SKIPPED=1`,
`ALLOWED_SKIPPED=1`, `CRITICAL_MISSING=0`, `SQLCMD_EXIT_CODE=0`, `SQL_ERROR_COUNT=0`,
`UNAUTHORIZED_SKIPS=0`, `@@TRANCOUNT=0`, `DB GATE PASS`.

Conteos de vistas antes y después: `uv_usuario=5011`, `uv_estudiante=6302`, `uv_docente=5`, `uv_grupo=5`,
`uv_sesion=15`, `uv_estudiante_grupo=6302`, `uv_asistencia=6350`, `uv_detalle_asistencia=6350`.
Residuos propios detectados: 0; restricciones QA temporales: 0. El contenedor temporal fue eliminado y el principal,
Keycloak, PostgreSQL, MinIO, ClamAV y observabilidad permanecieron operativos.

## 13. Correccion de fixtures y consolidacion de datos (2026-11-09)

### Cambios de codigo

- En los fixtures de asistencia, el mapeo ahora respeta el catalogo: `AN -> asistio=1`, `SJC -> asistio=0` y
  `EX -> asistio=0`. La prueba de resumen espera cuatro presentes; los dos detalles `EX` ya no cuentan como asistencia.
- Los escenarios D1 seleccionan un grupo realmente ajeno al estudiante y un estudiante con una sola fila de matricula
  activa en la asignatura. D1-06 exige el error contractual `DBCODE=EST_004`; D1-10 no supone que desactivar una
  matricula elimina resultados mientras haya otra activa.
- Las fixtures de reclamos excluyen estudiantes con historial previo cuando afirman conteos de solicitudes nuevas.
  Las de coordinacion seleccionan programas y decanos de la misma facultad.
- Las limpiezas MAINT y de volumen resuelven dependencias por claves exactas y abortan si hallan reclamos. Las fixtures
  MAINT-003G/H y runners B.2 validan DB Developer y `OPERACION/AMBIENTE` antes de escribir. Los runners locales usan
  `sql_server_asistencias` por defecto; CI sigue pasando `sqlserver` explicitamente.
- No cambiaron SP, vistas, funciones, tablas, migraciones ni permisos. No se ejecuto `deploy_schema.ps1`.

### RED/GREEN e integridad

| Comprobacion | Resultado |
|---|---|
| RED inicial | `CULM001_D1_D1_06_AJENA_NO_ES_REV_020` fallo porque el grupo seleccionado tambien matriculaba al estudiante A. Tras corregir ese escenario, D1-10 expuso una segunda matricula activa del mismo estudiante. |
| D1 focalizado final | **PASS**: D1-01..D1-10 y D1-12, incluido `D1_06_PROPIEDAD_ANTES_QUE_PLAZO`, `D1_10_SESIONES_MATERIA_ESTUDIANTE`, permisos y `@@TRANCOUNT=0`. D1-11 pasó en el gate de migración. |
| `test_summary.ps1` final | `TOTAL_EXPECTED=426`, `TOTAL_EXECUTED=595`, `PASSED=594`, `FAILED=0`, `SKIPPED=1`, `ALLOWED_SKIPPED=1`, `CRITICAL_MISSING=0`, `SQLCMD_EXIT_CODE=0`, `SQL_ERROR_COUNT=0`, `UNAUTHORIZED_SKIPS=0`, `@@TRANCOUNT=0`, **DB GATE PASS**. El unico skip es `XACT_STATE_MINUS_ONE_RUNTIME`. |
| B.2 fixtures y concurrencia | **PASS**: `CULM001_B2_SEG_02_FIXTURES_REPETIBLES`, cierres TOM-10/TOM-08 y pruebas de concurrencia. |
| Freeze manifest | **PASS**: `entries=10`, `post_freeze_superseded=4`, `post_freeze_work_item=11`, `culm001_d=7`. |
| PowerShell y guardas | **PASS**: parseo de `prepare_java_integration_fixture.ps1` y `test_culm001_b2.ps1`; preflight SQL devolvio `gestionasistenciadb|Developer Edition (64-bit)|MAINT_GUARDS_OK`. |
| Restricciones | **PASS**: `DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS` termino sin errores ni filas de violacion. |

### Datos revisados y decision

El respaldo previo a la actualizacion de MAINT-003G fue `C:\Users\josev\AsistenciasUCO\db-backups\gestionasistenciadb_copyonly_pre_maint003g_refresh_20261108.bak`;
SHA-256 `a2befd05211e3978a9e87323354062ba63a3084f17b420fee0aef5a0a172e9cb`. Se verifico con `RESTORE VERIFYONLY WITH CHECKSUM`.

| Registro | Evidencia por vistas `uv_*` | Decision |
|---|---|---|
| Detalles codigo 6352/6353 | `SJC/1` con un reclamo aceptado; `EX/1` con cuatro reclamos (dos aceptados y dos rechazados). Ambos estan en la sesion `B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E`, 2026-08-17 13:00 UTC. | No se alteraron. El historial de reclamos impide corregirlos sin identificar primero el flujo y la semantica historica que los creo. |
| Sesion futura | `B815DFC8-B813-4586-B901-CB9FD55AA590`, 2026-12-09 13:00 UTC: una toma MANUAL implicita cerrada, siete detalles (`SJC=6`, `EX=1`, todos `asistio=0`) y dos reclamos (uno aceptado y uno rechazado). | Se preserva. `esImplicita=1` es compatible con un backfill de la migracion 16, pero no prueba por si solo su procedencia; tampoco es un error que la toma este cerrada. |
| Fixture 2040 MAINT-003G | Se retiro la sesion sintetica antigua `8244100E-8447-4FE8-B1BC-876EA7E8FAF0`. El tag queda en `E8060D7E-D564-45B3-B245-F698A2F6762B`, 2026-11-09, con una toma cerrada, dos detalles (`AN=1`, `SJC=0`) y cero reclamos. No queda sesion de ese tag en 2040. | Depurada y recreada de forma idempotente con el respaldo anterior; sus dos filas siguen siendo requeridas por la fixture de integracion. |
| Estudiante-programa | `uv_estudiante_programa=5007`; 5007 IDs y 5007 pares estudiante-programa distintos; 5000 corresponden al set sintetico `DE0000`. | Se preserva; no se encontraron duplicados. |
| `uco-coordinador` | Cero coincidencias de correo/nombre/identificacion en `uv_coordinador`; la vista expone dos contextos de coordinacion activos. | Sin cambio: no se pudo enlazar el nombre de usuario externo con una identidad DB verificable; una asignacion de grupo no demuestra coordinacion formal. |

### Transferencia para Backend

- No hay SP ni vistas corregidas en este lote; por tanto, no cambian firmas ni columnas SQL consumidas. Los consumidores
  Java y la configuracion de despliegue no se modificaron.
- `GET /api/v1/estudiante/materias/{materiaId}/sesiones` conserva el contrato vigente de `usp_consultar_sesiones_materia_estudiante`
  (13 columnas: identidad/nombre/numero/codigo/semana, grupo y fechas, `fechaLimiteJustificacionUtc`,
  `plazoJustificacionVigente` y `totalRegistros`). El endpoint existente ya pasa `pagina` y `tamano`; no se agrego paginacion
  ni filtrado nuevo desde DB. Java debe seguir tratando las fechas `DATETIME2` como UTC literal.
- `POST /api/v1/asistencias/revisiones` conserva `usp_radicar_solicitud_revision_asistencia_v2`, su firma y codigos de
  catalogo. No se identifico un ajuste Java requerido por este diff. La semantica es `AN` presente, `SJC` ausencia sin
  justificar y `EX` ausencia justificada; ambas ausencias tienen `asistio=0`.
- En la siguiente fase, Backend/Angular debe validar visualmente historial docente/estudiante y reclamos con esos tres
  estados, y mostrar el limite de justificacion en su fecha UTC/local contractual. La revision general de paginacion y
  filtros sigue siendo de Backend. H-03 y `DB_PRINCIPAL_HARDENING` permanecen fuera de alcance por sus contratos vigentes.
