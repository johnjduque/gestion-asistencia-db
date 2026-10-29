---
name: procedimientos-internos-condiciones
description: >-
  Estándar canónico corporativo y reglas estructurales obligatorias para todos los procedimientos almacenados internos (*_interno) en gestionasistenciadb.
---

# Documentación Técnica de Arquitectura: Procedimientos Almacenados Internos (*_interno)

## Generalidades del Estándar Canónico Corporativo

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, parámetros de catálogo consumidos y flujo de control para **todos los Procedimientos Almacenados con sufijo `_interno`** en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias
1. **Inmutabilidad de Nombres Preexistentes**: Queda **estrictamente prohibido renombrar o modificar los nombres de los procedimientos almacenados internos (`*_interno`), tablas, vistas o funciones ya existentes**. La nomenclatura de los objetos creados es inmutable.
2. **Nombres de Variables UUID**: Toda variable, parámetro o columna `UNIQUEIDENTIFIER` inicia obligatoriamente con el prefijo `id` (ej. `@idTipoIdIdentificacion`, `@idCorrelacion`, `@idDocente`, `@idGrupo`, `@idEstudiante`, `@idPrograma`, `@idSesion`, `@idPerfil`).
2. **Parámetros de Salida Unificados**: Todo procedimiento expone exactamente:
   - `@mensajeUsuarioResultado NVARCHAR(4000) OUTPUT`
   - `@mensajeTecnicoResultado NVARCHAR(4000) OUTPUT`
   - `@estadoResultado BIT OUTPUT`
3. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - `DECLARE` únicamente ubicado entre el `AS` y el primer `BEGIN`.
   - Inicialización de GUIDs mediante `dbo.ufn_obtener_parametro_guid(@variable, 'MODULO/GENERAL', 'NOMBRE_PARAMETRO')`.
   - Limpieza de cadenas mediante `TRIM(@variable)`.
   - **Prohibido el uso de `ISNULL` o `COALESCE`**.
4. **Respuesta Inicial**: Limpieza e inicialización desde catálogo con `dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA')` y `@estadoResultado = 1`.
5. **Catálogo de Mensajes Centralizado**: Respuestas gestionadas a través de `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` en el mensaje técnico.
6. **Manejo Centralizado de Excepciones**: En el bloque `CATCH`, se invoca `dbo.usp_obtener_mensaje_catalogo` con `'SYS_001'` y se registra la traza mediante `dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto)`.
7. **Obligatoriedad de Consulta a Través de Vistas Base (`uv_*`)**: Toda lectura o validación de existencia de información dentro del procedimiento interno debe realizarse obligatoriamente por medio de las **vistas base (`uv_*`)** (ej. `uv_docente`, `uv_estudiante_grupo`, `uv_sesion`), estando prohibido realizar `SELECT` directo a tablas físicas del MER (salvo comprobaciones atómicas de PK `IF EXISTS (SELECT 1 FROM dbo.Tabla WHERE ...)`).

---

## Excepciones documentadas y patrones vigentes (REC4, 2026-10-29)

1. **Internos de resolución con `THROW`.**
   - Los internos que **resuelven** un identificador para un SP de lectura (ej. `usp_resolver_programa_coordinador_interno`, `usp_resolver_facultad_decano_interno`, `usp_resolver_periodo_kpi_interno`) pueden devolver el valor en un parámetro OUTPUT propio y, ante un error, hacer `THROW` con el código de catálogo (`VAL_001`, `KPI_001`, `GEN_001`) en lugar del triplete de mensajes.
   - Solo se usan desde SP de lectura (READ_QUERY_RESULTSET).
   - Los internos que **validan o escriben** mantienen el triplete OUTPUT.
2. **Interno de validación compartido.**
   - Se recomienda extraer a un `usp_validar_*_interno` la secuencia ejecutor, RBAC, existencia y titularidad cuando se repite en varios SP públicos.
   - Recibe el `@idUsuarioEjecutor` original (puede ser NULL y entonces responde `GEN_002`) y expone el triplete OUTPUT.
   - Ejemplo: `usp_validar_gestion_asignatura_coordinador_interno` (REC2).
3. **`ISNULL`/`COALESCE`:** permitidos solo en agregaciones, igual que en `procedimientos-externos-condiciones`.
4. **Lecturas con bloqueo:** dentro de una transacción, las lecturas con `UPDLOCK`/`HOLDLOCK` pueden ir a la tabla.
5. **Estilo:** `DECLARE` en la cabecera es obligatorio en el código nuevo. El código anterior no se reescribe solo por estilo.
