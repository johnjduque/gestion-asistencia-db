---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-26
---

# PLAN — SKILLS-BD lote 8: notificaciones

## Contexto

Lote 8 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 17 SP. Va en la rama larga
`refactor/skills-bd`, sobre el lote 7. Regla del lote: **no cambia el comportamiento de la app** (mismas firmas, mismos resultsets,
mismos códigos de rechazo y mismo flujo de error). Antes de tocar código se escribió `test/test_skills_lote8_caracterizacion.sql`
(los 6 internos del lote no tenían prueba directa) y se corrió sobre el código previo (pasaron los 6); después del refactor pasan
los 6, igual que las pruebas de dominio (outbox NOTIF-001, avisos de falta ATA, IDENT-001, NOTIF-002A, cierre de contrato).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Internos del outbox | `usp_registrar_notificacion_saliente_interno`, `usp_reservar_notificaciones_salientes_interno`, `usp_marcar_notificacion_entregada_interno`, `usp_registrar_fallo_notificacion_interno`, `usp_depurar_notificaciones_salientes_interno` | `DECLARE` en la cabecera (los de un paso se asignan con `SET` en ese paso), `PASO n`, lecturas sin bloqueo por las vistas nuevas. La reserva (`UPDLOCK, READPAST, ROWLOCK`), el `UPDATE` y el `DELETE` siguen en la tabla |
| Validador | `usp_validar_correo_institucional_personal_interno` | `PASO n`, `IF` con `BEGIN/END`, `TRY/CATCH` como los validadores de los lotes anteriores |
| Fachadas del outbox | `usp_registrar_notificacion_saliente`, `usp_reservar_notificaciones_salientes`, `usp_marcar_notificacion_entregada`, `usp_registrar_fallo_notificacion`, `usp_depurar_notificaciones_salientes` | `DECLARE` en la cabecera, `PASO n`, `SET XACT_ABORT ON` (salvo reservar, ver abajo), lecturas por vistas y `IIF` en lugar de `COALESCE`/`ISNULL` sobre variables |
| Verificación de correo | `usp_confirmar_verificacion_correo`, `usp_consultar_reenvio_verificacion_correo` | Usuario, ámbito, estudiante y tokens por vistas `uv_*`; `IF` con `BEGIN/END`; el bloqueo del token y el `UPDATE` de `Usuario` siguen en las tablas |
| Avisos de falta | `usp_registrar_aviso_falta_sesion`, `usp_consultar_sesiones_pendientes_aviso_falta`, `usp_consultar_faltas_sesion_aviso` | Sesión y avisos por `uv_sesion`/`uv_aviso_falta_sesion`; sin `ISNULL`; `TRY/CATCH` de lectura en las consultas |
| Contactos | `usp_consultar_contacto_notificacion` | `DECLARE` en la cabecera y `PASO n` |
| Vistas nuevas | `uv_notificacion_saliente`, `uv_estado_notificacion`, `uv_aviso_falta_sesion` | Delgadas, una tabla cada una, mismas columnas que la tabla. Inventario de `transaccion-procedimiento.md`: 112 vistas |
| Pruebas | `test/test_skills_lote8_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 6 IDs nuevos `SKL8_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 8 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`; condición nueva en E5 de `excepciones-skills-bd.md` | |

Las vistas nuevas no unen otras tablas, así que devuelven las mismas filas. Las vistas usadas en `usp_consultar_reenvio_verificacion_correo`
se revisaron como en el lote 7 (uniones por FK `NOT NULL`; las opcionales de `uv_grupo` y `uv_programa` son `LEFT JOIN`).

Sin migración: el lote solo cambia cuerpos de SP y agrega vistas; `deploy_schema.ps1` aplica todo `schema/views`. Ningún archivo
del Golden Path ni de los manifiestos congelados cambia.

## Diferencias observables (ninguna de negocio)

- Cuatro fachadas que escriben ganan `SET XACT_ABORT ON`: `usp_registrar_notificacion_saliente`, `usp_marcar_notificacion_entregada`,
  `usp_registrar_fallo_notificacion` y `usp_depurar_notificaciones_salientes`. Sus rechazos son tripletes (no errores) y sus internos ya
  tenían `XACT_ABORT ON`, así que el resultado no cambia; el backend las llama sin transacción externa.
- `usp_reservar_notificaciones_salientes` **no** gana `XACT_ABORT ON`: sus validaciones salen como `THROW 51000` y con `XACT_ABORT ON`
  condenarían la transacción del llamador. Al probarlo, `test/test_usp_reservar_notificaciones_salientes.sql` lo detectó (error 3930
  en el caso siguiente), así que se dejó como estaba y quedó anotado en la excepción E5.
- Los 3 SP del aviso de falta (`usp_consultar_sesiones_pendientes_aviso_falta`, `usp_consultar_faltas_sesion_aviso` y
  `usp_registrar_aviso_falta_sesion`) los crea la migración 51 con su texto original; el texto corregido llega por `deploy_schema.ps1`,
  que corre después de las migraciones. `test/test_ata_p1_migraciones.sql` compara los textos tras down -> up, así que ahora también
  repone esos 3 SP (y `uv_aviso_falta_sesion`) desde `schema/` antes de comparar, igual que ya hacía con los cuerpos de la 50.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban (las vistas nuevas quedan sin uso y se pueden borrar).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
