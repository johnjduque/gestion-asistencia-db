---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-11
---

# PLAN — PC: tomas de asistencia como puntos de control

Contrato: [CONTRACT.md](CONTRACT.md). Diseño completo: `informes/DISENO_TOMAS_PUNTOS_CONTROL_2026-11-11.md` (secciones B y E).

Paquetes de BD: **BD-1** núcleo del cálculo, BD-2 ciclo de vida de la toma, BD-3 reclamo por toma y BD-4 integración (migración 37, permisos, catálogos, addendum y documentación pública). BD-1 no crea migración ni permisos: las vistas nuevas son internas y `uv_asistencia_sesion_horas` / `uv_toma_asistencia` ya tienen su GRANT (`rol_asistencias_runtime_culm001_b2.sql`).

## BD-1: implementado

| Objeto | Cambio |
|---|---|
| `schema/views/uv_toma_punto_control.sql` | NUEVA. Una fila por toma: punto de control recortado, orden `(punto, numero)`, vecinos, minutos de los tramos vecinos y apertura de la toma siguiente por número. |
| `schema/views/uv_asistencia_tramo.sql` | NUEVA. Una fila por (cabecera `Asistencia`, tramo), `n + 1` tramos por cabecera, con la clasificación de §A.4. |
| `schema/views/uv_asistencia_sesion_horas.sql` | MODIFICADA. Minutos por tramo en lugar del reparto 1/n; las 14 columnas conservan nombre, orden y tipo; agrega al final `minutosSesion`, `minutosAsistidos`, `minutosFalta`, `minutosExcusa`, `minutosSinRegistro`, `tomasAusentes`, `tomasSinRegistro` y `codigoEstadoSesionEstudiante`. |
| `schema/views/uv_toma_asistencia.sql` | MODIFICADA (solo agrega al final): `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `fechaAperturaSiguienteUtc`. `horasToma` se conserva (1/n) y queda obsoleto. |
| `schema/views/uv_detalle_asistencia_v2.sql` | Solo comentario: `horasToma` obsoleto. |
| `test/test_pc_calculo_tramos.sql` | NUEVA: `PC_CAL_01`..`PC_CAL_14`, `PC_INV_01`, `PC_CAL_TRANCOUNT_ZERO`. |
| `test_suite.sql`, `test_summary.ps1` | Registro de la prueba y de sus IDs críticos. |
| `test/test_culm001_b2_horas.sql`, `test/test_culm001_d8_kpis_horas.sql`, `test/test_mass_period_close.sql` | Fixtures con aperturas repartidas y valores esperados recalculados con la regla nueva (ver abajo). |

Ningún archivo tocado está en un manifiesto `.sha256` (`DB_DEVELOP_FREEZE`, `DB_CULM001_D_POST_FREEZE`, `DB_LB004D_SUPPORT_BINDING`, `DB_UTC_D06_POST_FREEZE`, `DB_BASELINE_CONTRACT`).

Consumidores que cambian de valor sin editarse (leen columnas por nombre): ver diseño §B.2 (`uv_resumen_asistencia_estudiante_grupo`, `uv_resumen_asistencia_estudiante_programa_grupo`, los SP de asistencias por sesión, bitácora, detalle de reclamo, tendencia, KPIs, comparativas, alertas, cierre masivo y revisiones de cancelación).

## Desviaciones respecto al diseño

- **D-1 `horasSinRegistro`.** El diseño la calcula con los minutos (`minutosSinRegistro / 60`). Redondeando cada hora por separado a 6 decimales, las cuatro no siempre suman `horasSesion` (por ejemplo 20 + 20 + 80 min dan 1.999999). Para cumplir `PC_INV_01` de forma exacta, `horasSinRegistro = horasSesion − las otras tres`, y 0 cuando `minutosSinRegistro = 0` (así nunca es negativa). La diferencia con `minutosSinRegistro / 60` es como mucho de 0.000002 h.
- **D-2 Redondeo de horas.** `minutos / 60.0` en T-SQL trunca a 6 decimales (40 / 60.0 = 0.666666). Se usa `CAST(CAST(minutos AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6))`, igual que `ufn_horas_sesion`, que da los valores del contrato (0.666667, 1.333333, 1.666667).
- **D-3 Ventanas por sesión, no particionadas.** La vista propuesta (`ROW_NUMBER/LAG/LEAD ... PARTITION BY idSesion` sobre toda la tabla) no recibe el JOIN correlacionado por sesión: el optimizador recalculaba la ventana de todas las tomas por cada cabecera (más de 270 s para sumar 30 000 cabeceras). `uv_toma_punto_control` calcula las mismas ventanas dentro de un `CROSS APPLY` por `Sesion` (tomas de la sesión por `UQ_TomaAsistencia_Sesion_Numero`), con el mismo resultado y las mismas columnas. No hizo falta la función `ufn_tramos_asistencia`.
- **D-4 Agregado de tramos.** `uv_asistencia_sesion_horas` une los minutos con un `LEFT JOIN` a un agregado por (`idAsistencia`, `idEstudianteGrupo`, `idSesion`) en lugar de `OUTER APPLY`: las lecturas masivas se resuelven por conjuntos y los filtros por cualquiera de esas columnas se empujan.
- **D-5 `uv_toma_asistencia`** se une a `uv_toma_punto_control` por `idToma` **y** `idSesion`, para que un filtro por sesión llegue a la vista de puntos de control.
- **D-6 `esParcial` en una sesión cancelada** pasa a 0 (antes podía ser 1 con marcas AN y SJC), como define §A.6. El consolidado y `tieneFaltaSinJustaCausa` de una sesión cancelada siguen por marcas.

## Pruebas existentes actualizadas

Solo cambian valores que son consecuencia directa de la regla de tramos; cada cambio lleva un comentario `PC (puntos de control)`.

- `test_culm001_b2_horas.sql`: las tomas se abren en `inicio + (k − 1) · duración / n` (antes todas en el inicio; con tramos solo contaría la última). La apertura se trunca al segundo para que el redondeo a `DATETIME2(0)` no la pase al minuto siguiente.
  - HOR_01: el estudiante 1 (AN + SJC en 0 y 60 min de una sesión de 2 h) pasa de 1 h asistida / 1 h de falta / parcial / 50.00 % a 0 h / 2 h / no parcial / 100.00 %.
  - HOR_07: total de falta del periodo de 19 h a 21 h (HOR_01 y HKA del estudiante 1). Los demás valores de HOR_07 se calculan dinámicamente.
  - HOR_04 (1 / 1 / 2 h) y HOR_05 (3 h y 4 h) dan los mismos valores con aperturas repartidas.
- `test_mass_period_close.sql` (CULM001_C_HOR_10): las 3 tomas de cada sesión de 3 h se abrían todas en el inicio; con tramos solo contaba la última y la falta de la toma 1 de `@egTres` valía 0 h (el motor creaba 1 revisión en lugar de 2). Se abren en los minutos 0, 60 y 120; los valores esperados no cambian (los dos estudiantes siguen en 33 %).
- `test_culm001_d8_kpis_horas.sql`: tomas de S1 en los minutos 0 y 60. eA1 y eAB (AN + SJC en S1) pasan de 1 h asistida / 1 h de falta a 0 h / 2 h. Cambian: sanidad de eAB (1/2 → 0/3), comparativa de facultad (6 h, 30.00 → 8 h, 40.00), programas (A 4 h, 26.67 → 6 h, 40.00; B 4 h, 40.00 → 5 h, 50.00), tendencia semanal (6 h, 40.00 → 8 h, 53.33) y mensual (24.00 → 32.00), consolidado (G1, A) 33.33/26.67 → 20.00/40.00 y (G1, B) 10.00/40.00 → 0.00/50.00.

## Rendimiento (medido)

Volumen de prueba en una transacción revertida sobre la base local: 50 grupos × 20 sesiones × 30 estudiantes = 30 008 cabeceras, 90 014 detalles y 3 007 tomas (3 por sesión). Tiempos en ms, varias corridas (el equipo tiene carga variable; las cifras oscilan ±50 %):

| Consulta | Regla anterior | BD-1 |
|---|---|---|
| `SUM` sobre toda `uv_asistencia_sesion_horas` | 2 400 – 3 600 | 1 300 – 2 600 |
| `uv_asistencia_sesion_horas` de un grupo | 60 – 210 | 270 – 380 |
| `uv_asistencia_sesion_horas` de una cabecera | — | 40 – 170 |
| `uv_resumen_asistencia_estudiante_grupo` completa | 2 200 – 3 500 | 1 900 – 3 200 |
| `uv_resumen_asistencia_estudiante_grupo` de un grupo | 450 – 1 260 | 1 000 – 3 200 |
| `uv_resumen_asistencia_estudiante_grupo` de una matrícula | 220 – 690 | 330 – 620 |

Las lecturas masivas (KPIs, comparativas, tendencia, que agregan el resumen completo) no empeoran. La lectura del resumen de **un grupo** es de 2 a 3 veces más lenta: el agregado de `hs` de la vista de resumen se calcula por conjuntos sobre todas las cabeceras. Queda como observación para BD-4 (opciones: filtrar en la vista de resumen o un índice que incluya `razonCausa`; no se tocó la vista de resumen porque §B.2 la deja sin editar).

## BD-2: ciclo de vida de la toma (implementado)

| Objeto | Cambio |
|---|---|
| `schema/seed/35_parametros_toma_asistencia_qr.sql` | `TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION` = 20 (valor y valor por defecto). |
| `schema/seed/35_catalogos_toma_asistencia.sql` | Modo MANUAL con `marcaAusentesAlCerrar = 1`. `usp_cerrar_toma_asistencia` (con `@marcarAusentes` NULL) y `usp_cerrar_tomas_vencidas` marcan SJC sin tocar su código. |
| `usp_registrar_asistencias_toma` | `TOM_012` si la toma está cerrada y existe una toma con número mayor. Se valida una vez, después de bloquear la sesión (`UPDLOCK, HOLDLOCK` hasta el fin de la transacción) y la toma; la apertura toma el mismo bloqueo (D-7). |
| `usp_consultar_tomas_sesion` | Columnas al final: `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `esEditable`, `editableHastaUtc` (`DATETIME2(7)`). |
| `usp_consultar_resumen_tomas_sesion` | NUEVO. Reutiliza `usp_validar_docente_titular_sesion_interno` (sin copiar el bloque de validación). Sin `SET XACT_ABORT ON` (solo lectura). |
| `schema/seed/61_puntos_control_mensajes.sql` | NUEVO: `TOM_012`, `REV_026`..`REV_029`. |

## BD-3: reclamo por toma (implementado)

| Objeto | Cambio |
|---|---|
| `schema/tables/SolicitudRevisionAsistencia.sql` | Columnas `toma` y `razonCausaResolucion` (NULL). |
| `schema/tables/zz_foreign_keys.sql` | `FK_SolicitudRevisionAsistencia_TomaAsistencia`, `FK_SolicitudRevisionAsistencia_RazonCausaResolucion` e `IX_SolicitudRevisionAsistencia_Asistencia_Toma (asistencia, toma) INCLUDE (estado)`. Hash actualizado en `DB_CULM001_D_POST_FREEZE_MANIFEST`. |
| `usp_internal_radicar_solicitud_revision` | `@idToma` opcional al final. Paso 10b (después de la reejecución idempotente y antes del plazo): `TOM_001`, `REV_026`, `REV_027`; el INSERT guarda la toma. Hash actualizado en `DB_CULM001_D_POST_FREEZE_MANIFEST`. |
| `usp_radicar_solicitud_revision_asistencia_v4` | NUEVO. `@idToma` obligatorio (`GEN_002`); delega todo (incluida la transacción) en el interno (D-8). |
| `usp_resolver_solicitud_revision_asistencia` | `@codigoResultadoAprobacion` opcional al final; `REV_028`, `REV_029`; con toma solo cambia el detalle de esa toma; guarda `razonCausaResolucion`; idempotencia por resultado; auditoría con `idToma` y `resultadoAprobacion`. |
| `uv_solicitud_revision_asistencia` | Columnas al final: `idToma`, `numeroToma`, `codigoResultadoAprobacion`. |
| `uv_asistencia_toma_estudiante` | NUEVA (ver CONTRACT §C). |
| `usp_consultar_solicitudes_revision_estudiante`, `usp_consultar_detalle_solicitud_revision_docente` | Columnas al final (ver CONTRACT §C). |

No se tocan `usp_radicar_solicitud_revision_asistencia_v3`, `usp_consultar_tendencia_ausentismo`, `uv_sesion_estudiante_reclamo` (manifiesto CULM-001 D) ni `usp_consultar_solicitudes_revision_docente` y v2 (LB-004D).

## BD-4: integración (implementado)

- **Migración 37** `migrations/37_pc_tomas_puntos_control_up|down.sql`. El `up` copia en línea los objetos de BD-1 a BD-4 (tabla, sección PC de las FK, 8 vistas, 8 SP, permisos y mensajes), sube el tope a 20 solo si sigue en 4 y pone MANUAL a marcar ausentes. El `down` exige `CONFIRMAR_RETIRO_RECLAMO_TOMA = 1` si hay reclamos por toma (`THROW 50037` si no), restaura el texto de `develop` de cada vista y SP modificado, borra lo nuevo y deja el tope en 4 (solo si sigue en 20) y MANUAL sin marcar. `test/lib_componible.ps1` fija `CONFIRMAR_RETIRO_RECLAMO_TOMA = 0` en la cadena de downs de las pruebas componibles.
- **Permisos:** `schema/security/rol_asistencias_runtime_puntos_control.sql` (EXECUTE de v4 y del resumen; SELECT de `uv_asistencia_toma_estudiante`). La migración concede además SELECT a `uv_toma_punto_control` y `uv_asistencia_tramo`, que `deploy_schema.ps1` ya les da con el bucle `uv_*` de `rol_asistencias_runtime.sql` (D-9).
- **Pruebas:** ver [TEST_PLAN.md](TEST_PLAN.md). **Validación:** ver [VALIDATION.md](VALIDATION.md).

## Desviaciones de BD-2 a BD-4 respecto al diseño

- **D-7 TOM_012 una sola vez.** El diseño pedía validar también al confirmar. Con la sesión bloqueada (`UPDLOCK, HOLDLOCK`) desde antes de la validación hasta el fin de la transacción, ninguna apertura puede colarse; repetirla no cambia el resultado.
- **D-8 v4 sin andamiaje propio.** El diseño decía "copia de v3". v4 delega en el interno, que ya administra la transacción (propia o savepoint) y los errores; así no se duplica el bloque de v3 (SonarCloud de BD está cerca del límite de duplicación).
- **D-9 SELECT de las vistas internas.** El diseño las dejaba sin GRANT; `deploy_schema.ps1` les da SELECT con el bucle genérico `uv_*`, así que la migración lo replica para que una base migrada y una desplegada queden iguales.
- **D-10 Texto de TOM_012.** "Usa el reclamo para corregirla" se dirigía al docente, que no puede radicar; queda "Las correcciones se hacen por reclamo del estudiante.".
- **D-11 `esReclamable`** usa `ufn_calcular_fecha_limite_justificacion` sobre el fin de la sesión (el mismo criterio de `uv_sesion_estudiante_reclamo`) en vez de unir esa vista, que es más pesada; el resultado es el mismo para sesiones con tomas.
- **D-12 Columnas extra.** `uv_asistencia_toma_estudiante` agrega al final `idEstudiante` y `codigoEstadoTomaEstudiante` (útiles para el backend); `uv_toma_punto_control` y `uv_asistencia_tramo` agregan `idGrupo` (rendimiento).
- **D-13 Reintento del reclamo sin soportes.** La reejecución idempotente por correlación solo existe cuando hay soportes (igual que en v3); un reintento de v4 sin soportes responde `REV_027` en lugar de duplicar el reclamo.
- **D-14 Vista de resumen editada.** §B.2 dejaba `uv_resumen_asistencia_estudiante_grupo` sin editar; se editó solo para el rendimiento (agrupar y unir `hs` también por `idGrupo`), sin cambio de columnas ni de resultado para datos consistentes (la sesión de una cabecera es del grupo de su matrícula).

## Rendimiento (BD-4)

**Diagnóstico.** Con un filtro por grupo, el plan de `uv_resumen_asistencia_estudiante_grupo` calculaba los tramos de las 30 008 cabeceras (dos `Hash Match` sobre los 90 014 detalles, ventanas de las 1 008 sesiones y 60 020 lecturas de `SesionCancelacion`) y filtraba al final: el agregado `hs` se une por `idEstudianteGrupo` y el optimizador no puede deducir el grupo a partir de él.

**Cambio (mínimo, sin cambio de resultado y sin índices nuevos).** `uv_toma_punto_control` y `uv_asistencia_tramo` exponen al final `idGrupo` (grupo de la sesión); `uv_asistencia_sesion_horas` agrupa y une los tramos también por `idGrupo = s.grupo`; `uv_resumen_asistencia_estudiante_grupo` agrupa `hs` por (`idEstudianteGrupo`, `idGrupo`) y lo une por los dos. Así el filtro por grupo llega a `Sesion` (`UX_Sesion_Grupo_Codigo`) antes de las ventanas y el plan solo calcula los 1 800 tramos de las 600 cabeceras del grupo. También se probaron un índice cubriente (`UX_DetalleAsistencia_Asistencia_Toma` con `INCLUDE (razonCausa, asistio)`) y uno por `Asistencia.sesion`: no mejoraron de forma medible y encarecen las escrituras, así que no se agregaron. Pasar el agregado de tramos a `OUTER APPLY` por cabecera empeoró todo (resumen de un grupo 11 s), así que se descartó.

**Medición.** Mismo volumen que BD-1 (50 grupos × 20 sesiones × 30 estudiantes, 3 tomas por sesión: 30 008 cabeceras, 90 014 detalles), en una sola transacción revertida sobre la base local, cambiando las vistas dentro de ella. Mínimo – máximo en ms de 5 corridas (KPIs: 2; tendencia: 3). El equipo tiene carga variable y las cifras oscilan mucho.

| Consulta | Regla anterior (develop) | BD-1 | Final (BD-4) |
|---|---|---|---|
| `uv_resumen_asistencia_estudiante_grupo` de un grupo | 45 – 121 | 559 – 2 213 | **140 – 540** |
| `uv_asistencia_sesion_horas` de un grupo | 29 – 57 | 106 – 376 | 107 – 232 |
| `uv_resumen_asistencia_estudiante_grupo` completa | 1 056 – 1 710 | 1 729 – 2 444 | 1 755 – 3 398 |
| `SUM` sobre toda `uv_asistencia_sesion_horas` | 745 – 2 119 | 1 145 – 2 221 | 1 437 – 2 732 |
| `usp_consultar_kpis_institucion` | 5 247 – 7 901 | 5 923 – 9 393 | 6 530 – 10 489 |
| `usp_consultar_tendencia_ausentismo` | 1 198 – 2 400 | 2 507 – 3 686 | 3 005 – 5 086 |

- El resumen de un grupo baja de 0,56 s a 0,14 s (mínimos): queda en unas 3 veces la regla anterior (antes, de 4 a 12 veces).
- Las lecturas masivas (resumen completo, KPIs, tendencia) quedan como en BD-1 dentro del ruido, entre 1,2 y 2,5 veces la regla anterior: calcular tramos de todas las cabeceras cuesta más que contar marcas. Es inherente a la regla nueva.
- Observación aparte, anterior a PC: la primera ejecución de `usp_consultar_kpis_institucion` en una conexión nueva tardó entre 50 y 85 s con la regla anterior y con la nueva (compilación y plan sobre la vista de resumen); las siguientes, de 5 a 10 s. Conviene revisarlo en un work item propio.
