---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-11
---

# CONTRACT — PC: tomas de asistencia como puntos de control

Fuente: `informes/DISENO_TOMAS_PUNTOS_CONTROL_2026-11-11.md` (sección A), con las decisiones de John sobre la sección F:

- **F1:** se acepta el SUPUESTO-EX de §A.4.
- **F4:** las tomas MANUAL históricas sin marcar quedan "sin registro"; no se rellenan.
- **F7:** `horasToma` conserva su valor 1/n y queda **obsoleto** (expand & contract). Ningún cálculo de horas debe usarlo.
- **F8:** el estado PARCIAL queda como lo define §A.6.

Este contrato reemplaza el reparto de horas 1/n por toma de DEC-012 (CULM-001 B.2). DEC-024 (denominador de horas dictadas) no cambia.

## A.1 Entradas por sesión `s`

- `I = Sesion.fechaHoraInicio` y `F = Sesion.fechaHoraFin`, en UTC.
- `minutosSesion = DATEDIFF(MINUTE, I, F)` si `F > I`; si no, 0. Es el mismo criterio de `ufn_horas_sesion`, así que `horasSesion` no cambia.
- `cancelada = EXISTS SesionCancelacion(sesion = s)`.
- Tomas `T_1..T_n` de la sesión, en cualquier estado (abierta o cerrada), implícitas o no.

## A.2 Punto de control de cada toma

- `p_k = recorte(T_k.fechaAperturaUtc, I, F)`: si `apertura <= I`, entonces `I`; si `apertura >= F`, entonces `F`; si no, `apertura`. Si `F <= I`, `p_k = I`.
- Orden de los puntos: `(p_k, numero)`. Con datos reales coincide con `numero`; el desempate por `numero` hace el orden determinista.
- Tramos (`n + 1`):
  - tramo 0 = `[I, p_1]`, de borde, gobernado por `T_1`;
  - tramo k = `[p_k, p_{k+1}]` (k = 1..n-1), interno, gobernado por `T_k` y `T_{k+1}`;
  - tramo n = `[p_n, F]`, de borde, gobernado por `T_n`.
- Minutos de un tramo = `DATEDIFF(MINUTE, desde, hasta)`. La suma de los tramos de una sesión es **exactamente** `minutosSesion` (los términos se cancelan en cadena); no hay redondeo acumulado.

## A.3 Estado del estudiante en cada toma

Para la cabecera `Asistencia a` del estudiante en la sesión, el estado en `T_k` sale de `DetalleAsistencia(asistencia = a, toma = T_k)`:

| Estado | Marca |
|---|---|
| P | `AN` |
| A | `SJC` |
| E | `EX` |
| N | sin detalle, u otra razón (`CPVP`/`CPI`) |

Los literales `AN/SJC/EX` siguen [SUPUESTO-B-03] (catálogo cerrado), como en las vistas anteriores.

## A.4 Clasificación de un tramo

Sean `x` e `y` los estados de sus extremos (en un tramo de borde, `x = y` = estado de la toma del borde). Decide la primera condición que se cumpla:

| Prioridad | Condición | `codigoClasificacionTramo` |
|---|---|---|
| 0 | sesión cancelada | `SIN_REGISTRO` |
| 1 | `A ∈ {x, y}` | `AUSENTE` |
| 2 | `N ∈ {x, y}` | `SIN_REGISTRO` |
| 3 | `E ∈ {x, y}` (los dos son P o E) | `EXCUSADO` |
| 4 | `x = y = P` | `PRESENTE` |

- Un tramo interno es presente solo si el estudiante marcó las dos tomas; con una sola marcada es ausencia completa.
- **SUPUESTO-EX (aceptado, F1):** un tramo con extremos P o E y al menos una E es EXCUSADO (no suma falta ni horas asistidas). E junto a A da AUSENTE.
- N junto a P o E da SIN_REGISTRO.
- Las cuatro clasificaciones son un conjunto cerrado.

## A.5 Totales por (sesión, estudiante)

- `minutosAsistidos = Σ PRESENTE`, `minutosFalta = Σ AUSENTE`, `minutosExcusa = Σ EXCUSADO`.
- `minutosSinRegistro = minutosSesion − las tres anteriores` (= `Σ SIN_REGISTRO`).
- `horasAsistidas`, `horasFalta`, `horasExcusa` = `CAST(CAST(minutosX AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6))` (redondeo a 6 decimales, igual que `ufn_horas_sesion`). Se conservan nombres y tipos.
- `horasSinRegistro = horasSesion − horasAsistidas − horasFalta − horasExcusa`, y 0 cuando `minutosSinRegistro = 0`. Así las cuatro suman **exactamente** `horasSesion` y ninguna es negativa (ver PLAN, desviación D-1).

**Casos especiales**

- Sesión cancelada o sin tomas: asistidas, falta y excusa = 0; `minutosSinRegistro = minutosSesion` (igual que antes).
- Una sola toma: tramos `[I, p_1]` y `[p_1, F]`, ambos con el estado de `T_1`.
- Varias tomas en el mismo instante tras el recorte: tramos de 0 minutos. No pesan en las horas, pero la marca existe: cuenta en `tomasAusentes`, en `faltasSinJustaCausa` del resumen y se puede reclamar.
- Estudiante sin detalle en una toma: los tramos que la tocan quedan SIN_REGISTRO, salvo que el otro extremo sea A.
- Tomas MANUAL históricas sin marcar (F4): quedan sin registro.
- Matrícula sin cabecera `Asistencia`: no tiene fila (el resumen cuenta ese tiempo como sin registro por residuo).
- Cabecera sin detalle ni tomas: todo SIN_REGISTRO.

## A.6 Estado consolidado y estado del estudiante (`uv_asistencia_sesion_horas`)

- **`codigoRazonCausaConsolidado`:** si la sesión no está cancelada y `minutosSesion > 0`: `SJC` si `minutosFalta > 0`; si no `EX` si `minutosExcusa > 0`; si no `AN` si `minutosAsistidos > 0`. Si eso da NULL, o la sesión está cancelada o sin minutos, se usa la prioridad anterior por marcas (SJC > EX > AN). Ninguna fila que antes tenía consolidado lo pierde.
- **`esParcial`** = `minutosAsistidos > 0 AND minutosFalta > 0`.
- **`tieneFaltaSinJustaCausa`** = `minutosFalta > 0`; en una sesión cancelada o sin minutos, por marcas (`SJC` con `asistio = 0`) como antes.
- **`codigoEstadoSesionEstudiante`** (NUEVA; valores del enum `EstadoAsistenciaSesion`), la primera que se cumpla:

| Condición | Estado |
|---|---|
| sesión cancelada | `NO_DISPONIBLE` |
| `minutosSesion > 0` y `minutosAsistidos = minutosSesion` | `PRESENTE` |
| `minutosAsistidos = 0` y `minutosFalta > 0` | `AUSENTE` |
| `minutosAsistidos = 0`, `minutosFalta = 0` y `minutosExcusa > 0` | `JUSTIFICADA` |
| `0 < minutosAsistidos < minutosSesion` | `PARCIAL` ("Parcial: X de Y minutos") |
| todo sin registro | `NO_DISPONIBLE` |

## A.7 Casos de ejemplo (pruebas `PC_CAL_*`, `test/test_pc_calculo_tramos.sql`)

Sesión de 08:00 a 10:00 (120 min); salvo indicación, tomas en los minutos 0, 40 y 100.

| ID | Tomas (minuto: marca) | Tramos (min + clase) | Asist. / Falta / Excusa / SinReg | Estado |
|---|---|---|---|---|
| PC_CAL_01 | 0:AN, 40:AN, 100:AN | 0P, 40P, 60P, 20P | 120 / 0 / 0 / 0 | PRESENTE |
| PC_CAL_02 | 0:AN, 40:AN, 100:SJC | 0P, 40P, 60A, 20A | 40 / 80 / 0 / 0 | PARCIAL |
| PC_CAL_03 | 0:AN, 40:SJC, 100:AN | 0P, 40A, 60A, 20P | 20 / 100 / 0 / 0 | PARCIAL |
| PC_CAL_04 | 0:SJC, 40:AN, 100:AN | 0A, 40A, 60P, 20P | 80 / 40 / 0 / 0 | PARCIAL |
| PC_CAL_05 | 0:SJC, 40:SJC, 100:SJC | todo A | 0 / 120 / 0 / 0 | AUSENTE |
| PC_CAL_06 | una toma, 30:AN (o 30:SJC) | 30P, 90P (o A) | 120/0/0/0 (o 0/120/0/0) | PRESENTE (o AUSENTE) |
| PC_CAL_07 | aperturas −10, 60, 130 → puntos 0, 60, 120; AN, SJC, AN | 0P, 60A, 60A, 0P | 0 / 120 / 0 / 0 | AUSENTE |
| PC_CAL_08 | aperturas −10, −5 (ambas en 0) y 60; SJC, AN, AN | 0A, 0A, 60P, 60P | 120 / 0 / 0 / 0 | PRESENTE |
| PC_CAL_09 | 0:AN, 40:EX, 100:AN | 0P, 40E, 60E, 20P | 20 / 0 / 100 / 0 | PARCIAL |
| PC_CAL_10 | 0:AN, 40:(sin detalle), 100:AN | 0P, 40N, 60N, 20P | 20 / 0 / 0 / 100 | PARCIAL |
| PC_CAL_11 | 0:AN, 40:EX, 100:SJC | 0P, 40E, 60A, 20A | 0 / 80 / 40 / 0 | AUSENTE |
| PC_CAL_12 | sesión cancelada con marcas | todo N | 0 / 0 / 0 / 120 | NO_DISPONIBLE |
| PC_CAL_13 | PC_CAL_03 con la toma 2 cambiada a AN (reclamo aprobado PRESENTE) | como PC_CAL_01 | 120 / 0 / 0 / 0 | PRESENTE |
| PC_CAL_14 | PC_CAL_03 con la toma 2 cambiada a EX (reclamo aprobado JUSTIFICADA) | como PC_CAL_09 | 20 / 0 / 100 / 0 | PARCIAL |

**PC_INV_01:** para toda cabecera con tomas hay `n + 1` tramos, `Σ minutosTramo = minutosSesion` y `horasAsistidas + horasFalta + horasExcusa + horasSinRegistro = horasSesion`.

## Objetos y columnas (BD-1)

| Objeto | Tipo | Columnas |
|---|---|---|
| `uv_toma_punto_control` | vista NUEVA, interna (sin GRANT) | `idToma`, `idSesion`, `numero`, `fechaAperturaUtc`, `fechaCierreUtc`, `fechaHoraInicioSesion`, `fechaHoraFinSesion`, `estaSesionCancelada`, `fechaPuntoControlUtc`, `ordenPuntoControl`, `totalTomasSesion`, `idTomaAnterior`, `idTomaSiguiente`, `fechaPuntoAnteriorUtc`, `fechaPuntoSiguienteUtc`, `fechaAperturaSiguienteUtc`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `esUltimoPunto`, `idGrupo` (BD-4) |
| `uv_asistencia_tramo` | vista NUEVA, interna (sin GRANT) | `idAsistencia`, `idEstudianteGrupo`, `idSesion`, `ordenTramo` (0..n), `idTomaInicio` (NULL en el borde inicial), `idTomaFin` (NULL en el borde final), `fechaInicioTramoUtc`, `fechaFinTramoUtc`, `minutosTramo`, `codigoRazonCausaInicio`, `codigoRazonCausaFin`, `codigoClasificacionTramo` (`PRESENTE`, `AUSENTE`, `EXCUSADO`, `SIN_REGISTRO`), `idGrupo` (BD-4) |
| `uv_asistencia_sesion_horas` | vista MODIFICADA | las 14 columnas anteriores con su nombre, orden y tipo, y al final `minutosSesion`, `minutosAsistidos`, `minutosFalta`, `minutosExcusa`, `minutosSinRegistro` (INT), `tomasAusentes` (marcas SJC), `tomasSinRegistro` (tomas sin marca AN, SJC ni EX) y `codigoEstadoSesionEstudiante` (NVARCHAR(20)) |
| `uv_toma_asistencia` | vista MODIFICADA (solo agrega al final) | `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `fechaAperturaSiguienteUtc`; `horasToma` obsoleto |
| `uv_detalle_asistencia_v2` | sin cambio funcional | comentario: `horasToma` obsoleto |

## B. Ciclo de vida de la toma (BD-2)

- **Tope:** `TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION` = 20 (antes 4). La semilla cambia valor y valor por defecto; en una base existente la migración 37 sube el valor solo si sigue en 4 (respeta un valor administrado). `TOM_004` ya es paramétrico.
- **Toma MANUAL:** `ModoTomaAsistencia` MANUAL pasa a `marcaAusentesAlCerrar = 1`: al cerrarla (manual con `@marcarAusentes` NULL o automáticamente por vencimiento) quien no fue marcado queda SJC, igual que en la QR. `@marcarAusentes = 0` sigue permitiendo cerrar sin marcar. Las tomas MANUAL ya cerradas no se rellenan (F4).
- **Edición (regla 5, reemplaza [SUPUESTO-B-08]):** la toma abierta se edita; una toma cerrada se corrige solo mientras no exista una toma posterior de la sesión (`TOM_012` en cuanto se abre la siguiente); la última, mientras dure la ventana `[inicio − tolerancia, fin + margen)` (`SES_008` después). Después, la corrección es por reclamo del estudiante. La validación ocurre bajo el bloqueo de la sesión, el mismo que toma la apertura.
- **`usp_consultar_tomas_sesion`** agrega al final `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `esEditable` (ventana abierta y la toma es la abierta o no tiene posterior) y `editableHastaUtc` (apertura de la siguiente o, para la última, `ventanaCierreUtc`); NULL en la fila de una sesión sin tomas.
- **`usp_consultar_resumen_tomas_sesion(@idUsuarioEjecutor, @idCorrelacion, @idSesion)`** (NUEVO, `READ_QUERY_RESULTSET`, `THROW 51000`): una fila por matrícula activa del grupo con `idEstudiante`, `nombreCompletoEstudiante`, `minutosSesion`, `minutosAsistidos`, `minutosFalta`, `minutosExcusa`, `minutosSinRegistro`, `codigoEstadoSesionEstudiante`, `tomasAusentes`. Sin cabecera: todo sin registro y `NO_DISPONIBLE`.

## C. Reclamo por toma (BD-3)

- **Tabla:** `SolicitudRevisionAsistencia.toma` (NULL = reclamo de la sesión, legado) y `razonCausaResolucion` (AN o EX al aprobar), con FK sin cascada e índice `IX_SolicitudRevisionAsistencia_Asistencia_Toma (asistencia, toma) INCLUDE (estado)`.
- **Qué se reclama (F5):** solo una toma de la sesión (`TOM_001`) en la que el estudiante tiene SJC (`REV_026`), sin otra solicitud no retirada de esa toma (`REV_027`): un reclamo retirado permite radicar otro; uno rechazado o aprobado no. El plazo HU026B es el de la sesión. La validación bloquea cabecera, detalle y solicitudes de la toma.
- **Radicar:** `usp_radicar_solicitud_revision_asistencia_v4` (NUEVO) = v3 con `@idToma` obligatorio (`GEN_002`); resultset de 7 columnas (4 canónicas + `idSolicitudRevision`, `totalSoportes`, `idToma`). v3 (reclamo de la sesión) se conserva por compatibilidad (F6). `usp_internal_radicar_solicitud_revision` recibe `@idToma` opcional al final.
- **Resolver:** `usp_resolver_solicitud_revision_asistencia` recibe `@codigoResultadoAprobacion` opcional al final (NULL = EX; solo AN o EX, si no `REV_028`). Con toma: APROBADA + AN deja la toma en AN con `asistio = 1`; APROBADA + EX la deja en EX con `asistio = 0`; RECHAZADA no toca el detalle; solo cambia el detalle de esa toma. Sin toma (legado): AN da `REV_029`; EX conserva SES-04 (todos los SJC de la sesión a EX). La aprobación guarda `razonCausaResolucion`; repetir la misma acción con el mismo resultado es éxito sin escrituras; otro resultado sobre una solicitud aprobada (sin resultado guardado cuenta como EX) da `REV_002`. La auditoría agrega `idToma` y `resultadoAprobacion`.
- **Vista `uv_asistencia_toma_estudiante`** (NUEVA, la lee el backend): una fila por (cabecera, toma) con `idAsistencia`, `idEstudianteGrupo`, `idSesion`, `idToma`, `numeroToma`, `ordenPuntoControl`, `fechaPuntoControlUtc`, `codigoRazonCausa` (NULL = sin registro), `minutosTramoAnterior`, `minutosTramoSiguiente`, `idSolicitudRevision`, `codigoEstadoSolicitud`, `codigoResultadoAprobacion` (de la solicitud no retirada más reciente de la toma), `esReclamable` (SJC, sin solicitud no retirada, sesión no cancelada y plazo vigente), `idEstudiante` y `codigoEstadoTomaEstudiante` (`PRESENTE`, `AUSENTE`, `JUSTIFICADA`, `SIN_REGISTRO`).
- **Consultas:** `uv_solicitud_revision_asistencia` agrega `idToma`, `numeroToma`, `codigoResultadoAprobacion`; `usp_consultar_solicitudes_revision_estudiante` agrega `idToma`, `numeroToma`, `fechaPuntoControlUtc`, `codigoResultadoAprobacion`; `usp_consultar_detalle_solicitud_revision_docente` agrega esas cuatro más `codigoRazonCausaToma`, `minutosSesion` y `minutosAsistidos`. `usp_consultar_solicitudes_revision_docente` (LB-004D) y `usp_retirar_solicitud_revision_asistencia` no cambian.

## Mensajes nuevos

| Código | Tipo | Usuario | Técnico |
|---|---|---|---|
| `TOM_012` | BUSINESS_ERROR | La toma {} ya no se puede corregir porque se abrió la toma {}. Las correcciones se hacen por reclamo del estudiante. | Regla: la toma numero [{}] esta cerrada y ya se abrio la toma numero [{}]; solo se corrige por reclamo; sin escrituras. |
| `REV_026` | BUSINESS_ERROR | Solo puedes reclamar una toma en la que quedaste ausente. | Regla: el estudiante no tiene SJC en la toma [{}] de la sesion [{}]; sin escrituras. |
| `REV_027` | BUSINESS_ERROR | Ya existe un reclamo para esta toma. | Regla: la toma [{}] ya tiene la solicitud de revision no retirada [{}]; sin escrituras. |
| `REV_028` | VALIDATION_ERROR | El resultado de la aprobación debe ser PRESENTE o JUSTIFICADA. | Validacion: codigoResultadoAprobacion [{}] fuera de ASISTENCIA/CODIGO_RAZON_PRESENTE y ASISTENCIA/CODIGO_RAZON_EXCUSA; sin escrituras. |
| `REV_029` | BUSINESS_ERROR | La aprobación como presente solo aplica a reclamos de una toma. | Regla: la solicitud de revision [{}] es de la sesion completa (sin toma) y solo admite el resultado EX; sin escrituras. |
