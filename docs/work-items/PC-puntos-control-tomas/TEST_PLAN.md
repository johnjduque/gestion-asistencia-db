---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-11
---

# TEST_PLAN — PC: tomas de asistencia como puntos de control

Contrato: [CONTRACT.md](CONTRACT.md). Plan: [PLAN.md](PLAN.md). Todas las pruebas corren dentro de una transacción que se revierte; se ejecutan con `.\test_summary.ps1` (registradas en `test_suite.sql` y en la lista de IDs críticos).

## BD-1 — cálculo por tramos (`test/test_pc_calculo_tramos.sql`)

| ID | Qué verifica |
|---|---|
| `PC_CAL_01`..`PC_CAL_14` | La tabla de §A.7 del contrato: tramos y clasificación (`uv_asistencia_tramo`), minutos, horas, consolidado, `esParcial` y `codigoEstadoSesionEstudiante` (`uv_asistencia_sesion_horas`) y horas del resumen del estudiante. |
| `PC_INV_01` | Para toda cabecera con tomas: `n + 1` tramos, suma de minutos = `minutosSesion` y las cuatro horas suman `horasSesion`. |
| `PC_CAL_TRANCOUNT_ZERO` | La prueba no deja transacciones abiertas. |

## BD-2 — ciclo de vida de la toma (`test/test_pc_puntos_control.sql`)

| ID | Qué verifica |
|---|---|
| `PC_TOM_00_OBJETOS_Y_SEMILLAS` | Objetos, columnas, FK, índice y mensajes nuevos; tope `TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION` = 20; modo MANUAL con `marcaAusentesAlCerrar = 1`. |
| `PC_TOM_01_EDICION_HASTA_SIGUIENTE` | La toma 1 cerrada (última) se corrige; al abrir la toma 2, corregir la 1 responde `TOM_012` ("La toma 1 … la toma 2") sin escribir; la toma abierta sí admite registros. |
| `PC_TOM_02_ULTIMA_HASTA_MARGEN` | La última toma cerrada se corrige dentro del margen posterior al fin (fin hace 10 min); después de fin + margen responde `SES_008` sin escribir. |
| `PC_TOM_03_CIERRE_MANUAL_MARCA` | Cerrar una toma MANUAL con `@marcarAusentes` NULL marca SJC a los activos sin registro; el cierre automático (`usp_cerrar_tomas_vencidas`) de una MANUAL vencida también. |
| `PC_TOM_04_TOPE_20` | Con 20 tomas la 21 responde `TOM_004` ("… máximo de 20 tomas") sin crearla; con 19 se abre la 20. |
| `PC_TOM_05_CONSULTAS` | `usp_consultar_tomas_sesion`: `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramo*`, `esEditable` (0 para la toma 1 con la 2 abierta, 1 para la abierta) y `editableHastaUtc` (apertura de la siguiente o cierre de la ventana); sesión sin tomas con las columnas nuevas en NULL. `usp_consultar_resumen_tomas_sesion`: minutos por matrícula activa (incluida una sin cabecera: todo sin registro y `NO_DISPONIBLE`) y `THROW 51000` con `SEC_002` (no titular), `SEC_001` (no docente) y `GEN_002` (sin ejecutor) sin condenar la transacción. |

## BD-3 — reclamo por toma (`test/test_pc_puntos_control.sql`)

Sesión de 2 h que terminó hace unas 23 h (plazo HU026B vigente), tomas en los minutos 0, 40 y 100. Marcas: e1 AN/SJC/AN, e2 SJC/SJC/SJC, e3 AN/EX/(sin detalle), e4 sin cabecera, e5 AN/AN/SJC.

| ID | Qué verifica |
|---|---|
| `PC_REC_01_RADICAR_V4` | `uv_asistencia_toma_estudiante` (una fila por cabecera y toma, estado, minutos de los tramos vecinos, `esReclamable`); v4 radica la toma 2 de e1 y guarda la toma; v4 sin toma responde `GEN_002`. |
| `PC_REC_02_TOMA_SIN_AUSENCIA` | Reclamar una toma con AN, con EX o sin detalle responde `REV_026` sin escribir. |
| `PC_REC_03_DUPLICADO` | Un segundo reclamo no retirado de la misma toma responde `REV_027`. |
| `PC_REC_04_TOMA_DE_OTRA_SESION` | Una toma de otra sesión responde `TOM_001`. |
| `PC_REC_05_APROBADA_PRESENTE` | Aprobar con `@codigoResultadoAprobacion = 'AN'`: la toma pasa a AN con `asistio = 1`, e1 queda en 120/120 min (PRESENTE), la solicitud guarda el resultado y la auditoría lleva `idToma` y `resultadoAprobacion`. |
| `PC_REC_06_APROBADA_JUSTIFICADA_SOLO_LA_TOMA` | Aprobar sin resultado (EX): solo la toma reclamada pasa a EX; los otros SJC de e2 quedan intactos. |
| `PC_REC_07_LEGADO_SESION` | Reclamo de la sesión (v3): aprobar como AN responde `REV_029` sin escribir; aprobar como EX conserva SES-04 (todos los SJC de la sesión pasan a EX). |
| `PC_REC_08_IDEMPOTENCIA_Y_RESULTADO` | Repetir la aprobación con el mismo resultado (`' an '`) es éxito sin escrituras ni auditoría; otro resultado u otra acción responde `REV_002`; un resultado fuera de AN/EX responde `REV_028`. |
| `PC_REC_09_RETIRADO_PERMITE_OTRO` | Retirar el reclamo deja la toma reclamable y se radica otro; tras un rechazo la toma ya no es reclamable (`REV_027`). |
| `PC_REC_10_CONSULTAS_RECLAMOS` | `usp_consultar_solicitudes_revision_estudiante` y `usp_consultar_detalle_solicitud_revision_docente` exponen toma, número, punto de control, resultado, marca actual y minutos; un reclamo de la sesión devuelve las columnas de toma en NULL. |
| `PC_TRANCOUNT_ZERO` | La prueba no deja transacciones abiertas. |

## BD-4 — integración

| ID | Archivo | Qué verifica |
|---|---|---|
| `PC_SEG_01` | `test/test_public_objects.sql` | `EXECUTE` sobre v4 y el resumen, `SELECT` sobre `uv_asistencia_toma_estudiante`, `uv_asistencia_sesion_horas` y `uv_toma_asistencia`; el núcleo `usp_internal_radicar_solicitud_revision` sin permiso. |
| `PC_MIG_01_UP_DOWN_UP` | `test/test_pc_migracion_37.ps1` + `.sql` | Down (con confirmación) quita lo nuevo y restaura los textos de `develop`, el tope 4 y MANUAL sin marcar; up crea todo y concede permisos; up repetido no cambia nada; down→up reproduce el primer up. Componible (`-Despues 37`). |
| `PC_MIG_02_DOWN_SIN_CONFIRMACION` | `test/test_pc_migracion_37.ps1` + `_down_sin_confirmacion.sql` | Con un reclamo por toma y `CONFIRMAR_RETIRO_RECLAMO_TOMA = 0` el down aborta con `50037` sin cambios. |

## Pruebas existentes actualizadas (comentario `PC (puntos de control)`)

| Archivo | Antes | Después | Por qué |
|---|---|---|---|
| `test_culm001_b2_tomas.sql` TOM_00 | MANUAL `marcaAusentesAlCerrar = 0`; tope 4 | MANUAL = 1; tope 20 | Reglas 6 y tope aprobados. |
| `test_culm001_b2_tomas.sql` TOM_03 | Cierre de la MANUAL con `@marcarAusentes = NULL` sin marcar | Cierre con `@marcarAusentes = 0` (el escenario pide no marcar) | Con NULL ahora marca SJC y las pruebas siguientes cuentan con la toma 1 sin detalles. |
| `test_culm001_b2_tomas.sql` TOM_04 | 4 tomas y la quinta `TOM_004` ("4") | 20 tomas y la 21 `TOM_004` ("20") | Tope 20. |
| `test_culm001_b2_tomas.sql` TOM_07 | MANUAL con NULL: 0 marcados, 3 faltantes sin registro | 3 marcados SJC (`fueMarcadoAlCerrar = 1`), 4 detalles | Regla 6. |
| `test_culm001_b2_tomas.sql` CONSULTAS | `maximoTomas = 4`; tabla temporal de 33 columnas | `maximoTomas = 20`; 6 columnas nuevas al final | Tope 20 y columnas nuevas de `usp_consultar_tomas_sesion`. |
| `test_usp_consultar_detalle_solicitud_revision_docente.sql` | Lista de 30 columnas | 37 columnas (7 al final) | Columnas nuevas del detalle. |
| `test_consultas_reclamos_estudiante.sql`, `test_culm001_d2_soportes_categoria.sql`, `test_culm001_b2_horas.sql` | Tablas temporales con las columnas anteriores | Columnas nuevas al final | `INSERT … EXEC` exige las mismas columnas. |
| `test_contract_closure.sql` | — | v4 (7 columnas) y el resumen admitidos como no canónicos | SP públicos nuevos. |

TOM_09 (corrección de una toma cerrada) no cambia: corrige la última toma de la sesión, que sigue siendo editable; el caso con toma posterior lo cubre `PC_TOM_01`.
