# MEJORAS-SERGIO-2026-11-18 — Base de datos

Orden de John (2026-11-18): ejecutar las 13 mejoras reportadas por Sergio. El plan común (13 ítems, decisiones de los ítems 2 y
10) está en el work item homónimo del frontend. Aquí solo lo que toca la base de datos.

## Alcance BD

| Ítem | Cambio |
|---|---|
| 1 y 12 | **Retiro del tipo de vinculación del docente** (el sistema no lo administra). Migración `50_mejoras_sergio_retiro_tipo_vinculacion` (up/down idempotentes). |
| 5 | `usp_consultar_estudiantes_facultad_paginado` agrega `codigoTipoIdentificacion` (sigla del tipo de documento) al final del resultset. Cambio aditivo. |
| 2 y 10 | Sin cambios: el aviso al aprobar una solicitud de sesión (`usp_consultar_destinatarios_solicitud_sesion`) y la cancelación de sesión del docente (`usp_cancelar_sesion` + `usp_consultar_destinatarios_sesion_cancelada`, plantilla `SESION_CANCELADA`) ya existen. |
| 8 | Sin cambios: "estado financiero" y "promedio ponderado" no existen en la BD (búsqueda en `schema/`, `migrations/` y `test/`: 0 coincidencias). |

## Migración 50

- **Up:** `DROP` de `FK_DocentePrograma_TipoVinculacion`, de cualquier `DEFAULT` y de la columna `DocentePrograma.tipoVinculacion`;
  `DROP VIEW uv_tipo_vinculacion`; `DROP TABLE TipoVinculacion`; borra el parámetro `DOCENTE/TIPO_VINCULACION_DEFECTO` (con su
  historial y edición) y los mensajes `DOC_004` y `ERR_TIPO_VINCULACION_INVALIDO` (usuario y técnico). Valida el resultado
  (`THROW 55091..55093`). Los cuerpos de vistas y SP se despliegan con `deploy_schema.ps1`, como en la 48 y la 49 (obligatorio,
  ver `docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md`).
- **Down:** recrea la tabla con `PLA/MTI/CAT/OCA`, la vista, la columna (los vínculos existentes quedan con `CAT`, NOT NULL con
  `DF_DocentePrograma_tipoVinculacion`), la FK, el parámetro y los mensajes, y restaura el texto previo de las 2 vistas y los
  7 SP afectados. El tipo real que tenían los vínculos antes del up no se recupera.
- **Marcadores** (`scripts/migrar-marcadores.json`): la 50 se detecta por la ausencia de tabla, vista, columna, FK, parámetro y
  `DOC_004`; de la 05 se retiran los marcadores de `TipoVinculacion` y su FK (ya no siguen vigentes en develop).

## Objetos cambiados

- Tablas: `DocentePrograma` (sin `tipoVinculacion`), `TipoVinculacion` (retirada), `zz_foreign_keys.sql` (FK 40 retirada).
- Vistas: `uv_docente_programa`, `uv_auth_docente_programa` (sin columnas de tipo), `uv_tipo_vinculacion` (retirada).
- SP: `usp_vincular_docente_programa` y `_interno` (sin `@idTipoVinculacion`), `usp_actualizar_docente_programa` (sin
  `@idTipoVinculacion`), `usp_consultar_docentes_programa` (sin filtro ni columnas de tipo), `usp_consultar_resumen_docentes_programa`
  (una fila: `totalActivos`, `totalInactivos`), `usp_consultar_perfil_usuario` (el detalle del vínculo DOCENTE es la facultad),
  `usp_consultar_estudiantes_facultad_paginado` (+`codigoTipoIdentificacion`).
- Semillas: `16_tipo_vinculacion.sql` → `16_parametros_docente_programa.sql`; `17_mensaje_docente_programa.sql` (sin `DOC_004`);
  `63_val_mensajes_err_pendientes.sql` (sin `ERR_TIPO_VINCULACION_INVALIDO`). Catálogo regenerado (487 códigos).
- Pruebas y fixtures: inserciones de `DocentePrograma` sin la columna; pruebas de vincular, actualizar, directorio, resumen,
  perfil, migración 05 y decano (tipo de documento).
- Manifiesto `DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` actualizado para los 3 archivos de su lista que cambiaron.

## Compatibilidad

Rompe la firma de `usp_vincular_docente_programa` y `usp_actualizar_docente_programa` (se retira `@idTipoVinculacion`) y el
resultset de `usp_consultar_resumen_docentes_programa` y `usp_consultar_docentes_programa`: se despliega junto con el backend
de la misma rama.
