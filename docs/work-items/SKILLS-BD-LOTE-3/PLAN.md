---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-25
---

# PLAN — SKILLS-BD lote 3: parámetros, usuarios e identidad

## Contexto

Lote 3 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 18 SP. Regla del lote: **no cambia el
comportamiento de la app** (mismas firmas, mismos resultsets, mismos códigos de rechazo y mismo flujo de error). Antes de tocar código
se escribió `test/test_skills_lote3_caracterizacion.sql` y se corrió sobre el código de `develop` (los 9 casos de comportamiento
pasaron); después del refactor pasan los 10 (`SKL3_N01` verifica la estructura nueva).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Núcleos de usuario | `usp_actualizar_datos_usuario_interno`, `usp_cambiar_estado_usuario_interno`, `usp_corregir_documento_usuario_interno`, `usp_corregir_identidad_usuario_interno` | `PASO n`, `@idCorrelacionDefecto` en los mensajes, `IF` con `BEGIN/END`; el núcleo de identidad gana respuesta inicial y `TRY/CATCH` con `SYS_001` (relanza si hay transacción abierta: el fallo de auditoría sigue saliendo como `THROW 52531`) y lee el correo por `uv_usuario_autenticacion`. Las lecturas con `UPDLOCK, HOLDLOCK` siguen en la tabla |
| Validadores | `usp_validar_id_correlacion_esta_presente_interno` (`DECLARE` en la cabecera), `usp_validar_titularidad_jerarquica_interno` (`uv_administrador`), `usp_validar_perfil_existe_por_codigo_interno`, `usp_validar_tipo_identificacion_exista_por_id_interno`, `usp_validar_unicidad_usuario_interno`, `usp_validar_usuario_existe_por_id_interno` | Los cuatro últimos ya cumplían: el lote les agrega prueba directa |
| Utilidades transversales | `usp_obtener_mensaje_catalogo`, `usp_establecer_contexto_usuario_ejecutor` | Corregidas con la firma heredada (`@p_*`), excepción E8. Mensajes: `DECLARE` en la cabecera, sin `ISNULL`, `PASO n`, `TRY/CATCH` y `@estadoResultado BIT = NULL OUTPUT` opcional al final (ningún llamador cambia; el backend no lo llama). Contexto: `PASO n` y `TRY/CATCH` que relanza |
| SP públicos | `usp_consultar_perfil_usuario`, `usp_consultar_reenvio_activacion_cuenta`, `usp_corregir_identidad_usuario`, `usp_vincular_identidad_externa`, `usp_revocar_identidad_externa`, `usp_sincronizar_mensaje_usuario` | Lecturas por vistas `uv_*`, `IF` con `BEGIN/END`, `DECLARE` del `CATCH` a la cabecera, `TRY/CATCH` en las dos lecturas (relanzan, como las lecturas de lotes anteriores) |
| Vista nueva | `schema/views/uv_token_verificacion_correo.sql` | Solo `id`, `idUsuario` y `fechaEmisionUtc` de `dbo.TokenVerificacionCorreo`; nunca el hash. El runtime recibe `SELECT` como sobre todas las `uv_%` (`rol_asistencias_runtime.sql`) |
| Pruebas | `test/test_skills_lote3_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 10 IDs nuevos `SKL3_*` en `test_summary.ps1` |
| Documentación | `excepciones-skills-bd.md` (E8), addendum del lote 3 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`, ficha SP-015 e inventario (107 vistas) en `transaccion-procedimiento.md`, fila de `usp_obtener_mensaje_catalogo` en `especificacion_sp_endpoints.md` | |

Sin migración: el lote solo cambia cuerpos de SP y agrega una vista; `deploy_schema.ps1` lo aplica todo. Ningún archivo del Golden Path
ni de los manifiestos congelados cambia.

## Diferencias observables (todas de texto técnico, ninguna de negocio)

- `usp_actualizar_datos_usuario_interno`, `usp_cambiar_estado_usuario_interno` y `usp_corregir_documento_usuario_interno` escriben en el
  sufijo `Correlacion:` el GUID por defecto cuando reciben `@idCorrelacion = NULL` (antes quedaba vacío). Sus llamadores siempre pasan
  una correlación ya validada, así que en la app no cambia nada.
- Un error del motor dentro de `usp_corregir_identidad_usuario_interno` sin transacción abierta devuelve `SYS_001` en el triplete en
  vez de salir como excepción. Su único llamador (`usp_corregir_identidad_usuario`) siempre abre transacción con `XACT_ABORT ON`, así
  que ve el mismo error que antes.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban. La vista nueva se retira con
`DROP VIEW [dbo].[uv_token_verificacion_correo];` (nada fuera del lote la usa).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
