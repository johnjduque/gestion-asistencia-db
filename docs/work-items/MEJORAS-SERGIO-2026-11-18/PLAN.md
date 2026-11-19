# MEJORAS-SERGIO-2026-11-18 — Base de datos

Orden de John (2026-11-18): ejecutar las 13 mejoras reportadas por Sergio. El plan común (13 ítems, decisiones de los ítems 2 y
10) está en el work item homónimo del frontend. Aquí solo lo que toca la base de datos.

## Alcance BD

| Ítem | Cambio |
|---|---|
| 1 y 12 | **Retiro del tipo de vinculación del docente** (el sistema no lo administra). Migración `56_mejoras_sergio_retiro_tipo_vinculacion` (up/down idempotentes). |
| 5 | `usp_consultar_estudiantes_facultad_paginado` agrega `codigoTipoIdentificacion` (sigla del tipo de documento) al final del resultset. Cambio aditivo. |
| 2 y 10 | Sin cambios: el aviso al aprobar una solicitud de sesión (`usp_consultar_destinatarios_solicitud_sesion`) y la cancelación de sesión del docente (`usp_cancelar_sesion` + `usp_consultar_destinatarios_sesion_cancelada`, plantilla `SESION_CANCELADA`) ya existen. |
| 8 | Sin cambios: "estado financiero" y "promedio ponderado" no existen en la BD (búsqueda en `schema/`, `migrations/` y `test/`: 0 coincidencias). |

## Migración 56

- **Up:** `DROP` de `FK_DocentePrograma_TipoVinculacion`, de cualquier `DEFAULT` y de la columna `DocentePrograma.tipoVinculacion`;
  `DROP VIEW uv_tipo_vinculacion`; `DROP TABLE TipoVinculacion`; borra el parámetro `DOCENTE/TIPO_VINCULACION_DEFECTO` (con su
  historial y edición) y los mensajes `DOC_004` y `ERR_TIPO_VINCULACION_INVALIDO` (usuario y técnico). Si la fila de edición de
  otro parámetro lo usa como regla cruzada (`parametroDebeSerMenorQue`, `FK_CatalogoParametroEdicion_MenorQue`), esa regla se
  anula (`NULL`) y la fila se conserva: el otro parámetro sigue editable, solo pierde la comparación contra uno que ya no existe. Valida el resultado
  (`THROW 55691..55693`). Los cuerpos de vistas y SP se despliegan con `deploy_schema.ps1`, como en la 48 y la 49 (obligatorio,
  ver `docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md`).
- **Down:** recrea la tabla con `PLA/MTI/CAT/OCA`, la vista, la columna (los vínculos existentes quedan con `CAT`, NOT NULL con
  `DF_DocentePrograma_tipoVinculacion`), la FK, el parámetro y los mensajes, y restaura el texto previo de las 2 vistas y los
  7 SP afectados. El tipo real que tenían los vínculos antes del up no se recupera.
- **Marcadores** (`scripts/migrar-marcadores.json`): la 56 se detecta por la ausencia de tabla, vista, columna, FK, parámetro y
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

## HU090 retirada

HU090 (selector controlado de tipo de vinculación) queda **retirada el 2026-11-18** por orden de John y reporte de Sergio: el
sistema no administra el tipo de vinculación del docente (esta migración 56). En la BD no hay matriz de pruebas que la liste con
ese sentido; `docs/arquitectura/Plan_de_Trabajo_Historias_de_Usuario.md` usa el número HU090 para otra historia de la numeración
antigua ("Buscar la información de un usuario institucional") y no se toca.

## Orden de subida y despliegue

- **Subida y merge:** BD → BE → FE, cerrando los tres PR juntos. El CI de integración del backend usa la rama de la BD con el
  mismo nombre (`feat/mejoras-sergio-2026-11-18`) si existe; por eso la BD sube primero.
- **Despliegue:** primero la migración 56 (`56_mejoras_sergio_retiro_tipo_vinculacion_up.sql`) y después `deploy_schema.ps1`,
  nunca al revés: los cuerpos nuevos de vistas y SP ya no leen la columna, y los viejos quedan inválidos entre ambos pasos.
  Luego el backend y al final el frontend.
- **Manifiesto:** `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` se actualizó a propósito (3 archivos de su lista
  cambiaron: `63_val_mensajes_err_pendientes.sql`, `zz_foreign_keys.sql` y `migrar-marcadores.json`); mencionarlo en el PR.
