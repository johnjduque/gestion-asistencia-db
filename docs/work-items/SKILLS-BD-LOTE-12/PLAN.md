---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 12: tomas y QR

## Contexto

Lote 12 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 19 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 11. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Los 19 SP ya tenían prueba directa de dominio, así que no se agregó prueba de
caracterización nueva: antes de tocar código se corrieron sus 15 archivos de prueba sobre el código previo (todos pasaron) y después
del refactor dan exactamente el mismo resultado (`test_culm001_b1_festivos`, `test_culm001_b2_qr`, `test_culm001_b2_tomas`,
`test_ata_p1_tomas_denominador`, `test_pc_puntos_control`, `test_ident001_correo_verificacion`, `test_ident002_activacion_cuentas`,
`test_notoma_aviso_sin_toma`, `test_culm001_d7_retiro`, `test_dec076_dec077_creacion_grupo`, `test_mrm_solicitud_sesion`,
`test_val_pru15_periodo_cerrado`, `test_contract_closure`, `test_auditoria_bd_2026_11_22` y `test_skills_lote1_cobertura`).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Consultas de tomas | `usp_consultar_asistencias_toma_paginado`, `usp_consultar_faltantes_toma_paginado`, `usp_consultar_tomas_sesion`, `usp_consultar_tomas_qr_por_rotar` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| Avisos sin toma | `usp_consultar_destinatarios_aviso_sin_toma`, `usp_consultar_sesiones_pendientes_aviso_sin_toma`, `usp_registrar_aviso_sesion_sin_toma` | Igual (`IIF`/`IS NULL` en lugar de `ISNULL`); el registro conserva su `UPDLOCK, HOLDLOCK` y el `INSERT` en la tabla |
| Tomas | `usp_abrir_toma_asistencia`, `usp_cerrar_toma_asistencia`, `usp_registrar_asistencias_toma` | `PASO n`, `IF` con `BEGIN/END` y lecturas sin bloqueo por vistas; bloqueos y escrituras en las tablas |
| QR | `usp_abrir_qr_toma`, `usp_cerrar_qr_toma`, `usp_rotar_token_asistencia_toma`, `usp_rotar_token_asistencia_automatico`, `usp_registrar_asistencia_por_token` | Igual; las búsquedas `FORCESEEK` de la fila propia del registro QR siguen en las tablas (E7) |
| Correo | `usp_emitir_token_verificacion_correo`, `usp_consultar_token_verificacion_correo` | `DECLARE` del `CATCH` a la cabecera, `PASO n`, usuario por `uv_usuario`; el token se sigue buscando por hash en la tabla (E7) |
| Festivos automáticos | `usp_aplicar_festivos_automatico`, `usp_cargar_dias_festivos_automatico` | `PASO n` e `IIF` en lugar de `ISNULL` |
| Vista nueva | `uv_aviso_sesion_sin_toma` | Delgada, una tabla, sin cálculos. Inventario de `transaccion-procedimiento.md`: 126 vistas |
| Marca `SP_SISTEMA` | 30 SP de sistema no congelados (excepción E1) | Solo un comentario de cabecera; incluye SP de lotes anteriores que no la tenían. Los congelados la reciben en el lote 14 |
| Documentación | Addendum del lote 12 en `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`; E1 y E7 en `excepciones-skills-bd.md` | |

No se creó una vista para `TokenVerificacionCorreo`: el rol de runtime tiene `SELECT` sobre todas las `uv_%` y una vista con el hash
del token lo dejaría legible desde el backend (mismo motivo de E7 para el token QR).

Sin migración: el lote solo cambia cuerpos y comentarios de SP y agrega una vista; `deploy_schema.ps1` aplica todo `schema/views`.
Ningún archivo del Golden Path ni de los manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

Ninguna: se comparó `sys.dm_exec_describe_first_result_set_for_object` antes y después en los 19 SP y los metadatos son idénticos.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (la vista nueva queda sin uso y se puede borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
