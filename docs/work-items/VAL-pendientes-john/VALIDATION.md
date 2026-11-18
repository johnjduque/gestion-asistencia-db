---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-18
---

# VAL-pendientes-john (BD) - VALIDATION

Fecha: 2026-11-17/18. Rama `fix/VAL-pendientes-john` sobre `origin/develop` d659ad6. Sin build de Maven en paralelo. La BD
compartida de desarrollo (`sql_server_asistencias`) no se tocó y la migración 49 NO se aplicó en ella (se aplica después de unir).

## Compuerta de BD

Instancia SQL Server 2022 Developer desechable (`sql_gate_valpj`, collation `SQL_Latin1_General_CP1_CI_AS`, sin puerto publicado,
clave generada en la corrida y nunca impresa; contenedor borrado al terminar). Base creada desde cero, mismo orden que la CI:
`freeze-manifest.ps1 -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1 -Modo Detectar`, `-Modo Baseline`, `-Modo Estado`,
`prepare_lb004d_fixture.ps1`, `test_summary.ps1`, `cleanup_lb004d_fixture.ps1`.

| Dato | Valor |
| :--- | :--- |
| Inicio / fin | 2026-11-17 21:37:06 / 22:00:03 (UTC-5) |
| `deploy_schema.ps1` | rc 0 |
| `migrar.ps1 -Modo Detectar` | `total=49 detectadas=49 ausentes=0 parciales=0 sin_marcadores=0 contigua_hasta=49` |
| `-Modo Baseline` / `-Modo Estado` | rc 0 / rc 0: `total=49 registradas=49 pendientes=0 deriva=0` |
| `TOTAL_EXPECTED` / `TOTAL_EXECUTED` | 784 / 963 |
| `PASSED` / `FAILED` | 962 / 0 |
| `SKIPPED` / `ALLOWED_SKIPPED` | 1 / 1 (`XACT_STATE_MINUS_ONE_RUNTIME`) |
| `CRITICAL_MISSING` / `SQLCMD_EXIT_CODE` / `SQL_ERROR_COUNT` / `UNAUTHORIZED_SKIPS` | 0 / 0 / 0 / 0 |
| `@@TRANCOUNT` | 0 |
| Resultado | `DB GATE PASS`, rc 0 |
| Ids nuevos | 17 de 17 `TEST_PASS` (5 `VAL_PRU13_*`, 12 `VAL_PRU15_*`) |

Otras verificaciones:

| Comando | Resultado |
| :--- | :--- |
| `test/test_val_migrar_detectar.ps1` | 8 de 8 `TEST_PASS` (incluye `VAL_MDET_06_APLICAR_EN_ORDEN` con la 49) |
| `test/test_val_migrar.ps1` | 7 de 7 `TEST_PASS` |
| `scripts/freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11 culm001_d=81` |
| `scripts/lb004d-manifest.ps1 -Mode Verify` | `LB004D_MANIFEST_OK entries=9` |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=489` |
| Migración 49 up, down, down, up, up (a mano sobre la base de la compuerta) | rc 0 en las cinco; tras el down no quedan columna, núcleo ni mensajes; los siete SP restaurados compilan |
| Relleno de la 49 (a mano) | período con cierre auditado después de `fechaFin` queda cerrado con el instante del PRIMER cierre; cierre auditado el día de `fechaFin` (anticipado) y período sin auditoría quedan en NULL |

Corridas previas de la compuerta (corregidas en esta rama, no son evidencia de PASS):

1. Primera corrida: `test_mass_period_close.sql` falló con `PER_007` en vez de `RCN_012` y cortó la suite. Causa ajena a esta rama:
   la prueba crea el período con `fechaFin = GETDATE() - 1` y `GETDATE()` del contenedor está en UTC; entre las 19:00 y las 24:00
   de Bogotá ese día todavía es "hoy" en hora local, así que desde FIX-CIERRE-002 el período cuenta como no terminado. Se movió a
   `GETDATE() - 2` en `test_mass_period_close.sql` (dos períodos), `test_rec3_falla_intermedia_transaccion.sql` (TX-03) y
   `test/fixtures/culm001_c_cierre_fixture.sql`; la intención (período ya terminado) no cambia. En la misma corrida
   `VAL_MDET_06` falló porque la primera versión de la 49 llevaba los cuerpos de los SP y el cierre masivo lee
   `uv_periodo_academico.estado`, que llega solo por despliegue; la 49 quedó como la 48 (mensajes y columna; SP por `deploy_schema`).
2. Segunda corrida: `test_val_pru15_periodo_cerrado.sql` usaba tablas temporales `#r...` que otra prueba de la misma sesión ya
   había creado con otras columnas; se renombraron (`#p15*`).

## RED antes del cambio (PRU-15)

Esquema de `origin/develop` desplegado en la misma instancia: `test_val_pru15_periodo_cerrado.sql` pasa `VAL_PRU15_00` y falla en
`VAL_PRU15_01` (no existe `fechaCierreUtc`: el cierre no marca el período). Con el código de develop el segundo cierre responde
`GEN_004` y vuelve a auditar (ya documentado en FIX-CIERRE-002) y las tomas, lotes y reclamos de un período cerrado se aceptaban.
PRU-13 en develop: 5 de 5 `TEST_PASS` sin cambio de lógica (no apareció ningún error del plazo).

## Pruebas existentes ajustadas por la regla nueva

| Prueba | Antes | Ahora |
| :--- | :--- | :--- |
| `test_fix_cierre_001_cierre_masivo.sql` FIX001_CIE_03 | Cerraba el mismo período dos veces (por nombre y por código numérico), las dos con éxito | Entre las dos llamadas reabre el período (`fechaCierreUtc = NULL`, solo el fixture): sigue probando la resolución por nombre y por código |
| `test_culm001_c_cierre_masivo.sql` C-DB-44 | Volvía las matrículas a A y cerraba otra vez el período ya cerrado en C-DB-43 | Además de las matrículas reabre el período (solo el fixture); la aserción (umbral inválido no bloquea) no cambia |

Ninguna aserción se relajó. Ningún fixture toma asistencia en un período ya cerrado por el cierre masivo.

## SEG-11: retiro de la columna `password` (no ejecutado)

La orden pedía probar primero que nada escribe ni lee `Usuario.password`. La prueba no se cumple:

| Hallazgo | Dónde |
| :--- | :--- |
| Se escribe en cada alta | `usp_sincronizar_usuario_interno` exige `@password` no vacío (paso F) y lo inserta; la columna es `NOT NULL` |
| Se pasa en las altas | `usp_crear_decano` (+ `_con_facultad`, `_interno`), `usp_crear_coordinador` (+ `_con_programa`, `_interno`), `usp_registrar_estudiante_en_grupo`, `usp_admitir_estudiante` (exige el hash para persona nueva), `usp_internal_matricular_por_token` / `usp_registrar_estudiante_por_token_publico` (exige `@password`), `usp_vincular_docente_programa` (usa `@password IS NULL` para decidir el modo) |
| El backend la llena | 7 repositorios mandan `@password`. Para las altas hechas por otra persona es el hash de un secreto aleatorio (`ActivacionCuentaService.credencialLegadaInutilizable`), pero en la matrícula pública por QR (`RegistrarEstudiantePorTokenUseCaseImpl:78`) es el BCrypt de la contraseña que el estudiante escribe: un almacén de credenciales real |
| Se lee | Vistas `uv_usuario_autenticacion.password` y `uv_administrador.passwordUsuario`; no se encontró lector en el backend; la lee `test/test_user_dean_close.sql` |
| Pruebas y semillas | 78 archivos SQL de prueba, fixture o semilla insertan `Usuario.password`; 14 IT/fixtures del backend |

Retirarla exige expand/contract: dejar los `@password` como parámetros ignorados (AGENTS.md §5, sin romper firmas), quitar la
escritura y las exigencias de los SP, quitar el hash en el backend y en la matrícula QR, rehacer las dos vistas y ~90 pruebas, y
solo después la migración con DROP. Queda pendiente de decisión de John; no se cambió nada de SEG-11 en esta rama.
