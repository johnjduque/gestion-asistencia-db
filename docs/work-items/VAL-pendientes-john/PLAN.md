---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-18
---

# VAL-pendientes-john (BD) - PLAN

Rama `fix/VAL-pendientes-john` desde `origin/develop` d659ad6. Filas de la lista de chequeo
`informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`: PRU-13, PRU-15 y SEG-11.

## PRU-13: borde exacto del plazo de reclamo (solo pruebas)

Sin cambio de lógica. Prueba nueva `test/test_val_pru13_borde_plazo_reclamo.sql` (ids `VAL_PRU13_*`):

| Id | Qué prueba |
| :--- | :--- |
| `VAL_PRU13_01_FN_ULTIMO_MINUTO_LOCAL` | `ufn_calcular_fecha_limite_justificacion` con entradas fijas: un minuto antes del límite es 23:59 local del último día (se admite) y el límite es 00:00 local del día siguiente (vencido), con el N de la semilla y con N = 0 |
| `VAL_PRU13_02_FN_FRONTERA_DIA_LOCAL` | Fin 23:59:59.9999999 y 00:00:00 locales (el mismo día UTC): límites separados por un día; con `TIEMPO/ZONA_HORARIA_SQLSERVER` = UTC el corte se mueve con el parámetro |
| `VAL_PRU13_03_SP_ULTIMO_MINUTO_VALIDO` | `usp_radicar_solicitud_revision_asistencia_v3` con el reloj real: la sesión que terminó a las 00:00 locales de hoy-N se admite y su límite es mañana 00:00 local (último minuto válido hoy 23:59), con N = 0, 1 y el de la semilla |
| `VAL_PRU13_04_SP_PRIMER_MINUTO_VENCIDO` | La sesión que terminó un instante antes (23:59:59.9999999 locales de hoy-N-1) responde `REV_020` sin escribir, con el último día = ayer y el límite = hoy 00:00 local |

El reloj del motor no se puede fijar: el borde del "ahora" se prueba sobre la función (entradas fijas) y el borde real del SP se
prueba moviendo el fin de la sesión al instante exacto en que cambia el resultado (00:00 local frente a un instante antes).

## PRU-15: regla de período cerrado (decisión de John, 2026-11-18)

Modelo de estado: `uv_periodo_academico.estado` (PLANEACION, ACTIVO, CERRADO) se calcula por fecha y no se persiste; el cierre
masivo ya exigía `estado = CERRADO` (FIX-CIERRE-002, `PER_007`). Para que exista un período "cerrado" distinto de "terminado" se
persiste el cierre:

| # | Cambio |
| :-- | :--- |
| 1 | Columna `PeriodoAcademico.fechaCierreUtc datetime2(7) NULL`. La escribe `usp_ejecutar_cierre_masivo_periodo` en un cierre exitoso (no en un cierre bloqueado por `RCN_012`). |
| 2 | Núcleo nuevo `usp_validar_periodo_abierto_sesion_interno` (`PER_008`, sin GRANT). Lo llaman `usp_validar_sesion_ventana_registro_interno` (paso 2.7: abrir toma o QR, lote por toma, lote por sesión y registro por token), `usp_cerrar_toma_asistencia`, `usp_internal_radicar_solicitud_revision` (v2, v3 y v4), `usp_radicar_solicitud_revision_asistencia` (v1), `usp_resolver_solicitud_revision_asistencia` (solo reclamos pendientes; el reintento de una decisión ya aplicada sigue idempotente) y `usp_retirar_solicitud_revision_asistencia`. |
| 3 | Segundo cierre: `usp_ejecutar_cierre_masivo_periodo` bloquea la fila del período al abrir su transacción (primer bloqueo) y, si ya tiene `fechaCierreUtc`, responde `PER_009` con la fecha local del primer cierre, sin escribir ni auditar. |
| 4 | Mensajes `PER_008` y `PER_009` en `schema/seed/17_mensajes_periodo_academico.sql`. |
| 5 | Migración 49 (`49_val_periodo_cerrado_up/down.sql`): columna, relleno desde la auditoría `CIERRE_MASIVO_PERIODO` SUCCESS de períodos ya terminados (un cierre auditado antes de `fechaFin` no cierra el período), mensajes y cuerpos de los SP. El down restaura el texto de develop de los siete SP, borra el núcleo y los mensajes y quita la columna. Marcadores en `scripts/migrar-marcadores.json`. |

Fuera de la regla, a propósito: un período terminado por fecha pero sin cierre masivo sigue admitiendo reclamos y correcciones
(el plazo de reclamo puede pasar de `fechaFin`); `usp_cerrar_tomas_vencidas` (el job) sigue cerrando tomas abiertas;
`usp_cerrar_qr_toma` y la rotación de tokens QR no se tocaron (trabajo de Sergio; abrir QR y registrar por token sí quedan
cubiertos por el validador de ventana).

Pruebas: `test/test_val_pru15_periodo_cerrado.sql` (ids `VAL_PRU15_*`), rojas antes del cambio.

Frozen: no se modificó ningún archivo congelado (`usp_registrar_asistencias_sesion` queda cubierto por el validador de ventana que
ya llamaba). Manifiesto `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` actualizado para `usp_internal_radicar_solicitud_revision.sql` y
`scripts/migrar-marcadores.json`.

## SEG-11: retirar la columna `password` (NO ejecutado)

La condición previa de la orden ("probar que nada la escribe ni la lee") no se cumple. Ver `VALIDATION.md`, sección SEG-11. No se
cambió nada de SEG-11 en esta rama.
