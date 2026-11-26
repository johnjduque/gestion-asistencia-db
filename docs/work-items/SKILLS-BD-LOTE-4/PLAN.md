---
status: active
type: work-item
scope: database
owner: db-team
last-reviewed: 2026-11-25
---

# PLAN — SKILLS-BD lote 4: decano, facultad, coordinador y programas

## Contexto

Lote 4 del plan por lotes del 2026-11-25 (`informes/PLAN_LOTES_SKILLS_BD_2026-11-25.pdf`), 23 SP. Regla del lote: **no cambia el
comportamiento de la app** (mismas firmas, mismos resultsets, mismos códigos de rechazo y mismo flujo de error). Antes de tocar código
se escribió `test/test_skills_lote4_caracterizacion.sql` y se corrió sobre el código de `develop` (los 8 casos de comportamiento
pasaron); después del refactor pasan los 9 (`SKL4_N01` verifica la vista nueva).

## Cambios

| Grupo | Objetos | Detalle |
|---|---|---|
| Altas de rol | `usp_crear_decano_interno`, `usp_crear_coordinador_interno`, `usp_crear_decano_con_facultad` | `DECLARE` en la cabecera, lecturas por `uv_decano_rol`, `uv_coordinador_identidad` y `uv_tipo_identificacion`, `IF` con `BEGIN/END`; los dos internos ganan `TRY/CATCH` con `SYS_001` que relanza si hay transacción abierta |
| Resolvers y validadores | `usp_resolver_facultad_decano_interno`, `usp_resolver_institucion_administrador_interno`, `usp_resolver_programa_coordinador_interno`, `usp_validar_programa_en_facultad_interno`, `usp_validar_programa_academico_interno`, `usp_validar_coordinador_de_facultad_interno` | `PASO n`, `DECLARE` en la cabecera, `IF` con `BEGIN/END`; los que rechazan con `THROW` ganan `TRY/CATCH` que relanza (sin triplete, misma firma). Las lecturas con `UPDLOCK, HOLDLOCK` siguen en la tabla |
| Núcleos de facultad y programa | `usp_actualizar_facultad_interno`, `usp_cambiar_estado_facultad_interno`, `usp_insertar_programa_academico_interno`, `usp_actualizar_programa_academico_interno`, `usp_cambiar_estado_programa_academico_interno` | Solo `PASO n` |
| Fachadas | `usp_cambiar_estado_decano`, `usp_cambiar_estado_coordinador`, `usp_actualizar_coordinador`, `usp_actualizar_programa_academico`, `usp_cambiar_estado_programa_academico` | Ámbito por vistas, `@idCorrelacionDefecto`, `DECLARE` del `CATCH` a la cabecera, `IF` con `BEGIN/END`, `PASO n` y `SET XACT_ABORT ON` donde faltaba |
| Consultas | `usp_consultar_coordinadores_facultad_paginado`, `usp_consultar_estructura_facultad`, `usp_consultar_programas_academicos`, `usp_consultar_programas_creditos_facultad_paginado` | Lecturas por vistas, sin `ISNULL` fuera de agregaciones, `DECLARE` en la cabecera, comentario del `CATCH` de lectura (relanza, como en los lotes anteriores) |
| Vista nueva | `schema/views/uv_decano_rol.sql` | `id`, `idUsuario` y `estaActivoRolDecano` de `dbo.Decano`. Hace falta porque `uv_decano.estaActivoDecano` combina usuario y facultad y `uv_decano_identidad` no trae `Decano.estado`; no se cambia la forma de ninguna vista existente. El runtime recibe `SELECT` como sobre todas las `uv_%` |
| Pruebas | `test/test_skills_lote4_caracterizacion.sql` (nuevo, en `test_suite.sql`) | 9 IDs nuevos `SKL4_*` en `test_summary.ps1` |
| Documentación | Addendum del lote 4 en `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`; inventario (108 vistas) en `transaccion-procedimiento.md` | No hace falta excepción nueva |

Sin migración: el lote solo cambia cuerpos de SP y agrega una vista; `deploy_schema.ps1` lo aplica todo. Ningún archivo del Golden Path
ni de los manifiestos congelados cambia.

## Diferencias observables (todas de texto técnico o de errores del motor, ninguna de negocio)

- `usp_validar_coordinador_de_facultad_interno`, `usp_cambiar_estado_coordinador` y `usp_actualizar_coordinador` escriben en el sufijo
  `Correlacion:` el GUID por defecto cuando la correlación llega `NULL` (antes quedaba vacío). En las fachadas una correlación `NULL`
  ya se rechaza en el paso 1 con `CORR_001`, y el resultset sigue devolviendo el `idCorrelacion` recibido.
- Un error del motor dentro de `usp_crear_decano_interno`, `usp_crear_coordinador_interno` o `usp_validar_programa_academico_interno`
  sin transacción abierta devuelve `SYS_001` en el triplete en vez de salir como excepción. Todos sus llamadores abren transacción
  antes de invocarlos, así que ven el mismo error que antes.

## Reversión

Revertir el PR y volver a correr `deploy_schema.ps1` deja los SP como estaban. La vista nueva se retira con
`DROP VIEW [dbo].[uv_decano_rol];` (nada fuera del lote la usa).

## Actualizar una base local

`deploy_schema.ps1` (no hay migraciones nuevas en este lote).

## Validación

Se reprodujeron los pasos del CI en un SQL Server 2022 limpio: `freeze-manifest -Mode Verify`, `deploy_schema.ps1`, `migrar.ps1`
(Detectar, Baseline y Estado), la fixture LB-004D y `test_summary.ps1`.
