# Documentación Técnica de Arquitectura: Procedimientos Almacenados Públicos / Orquestadores (Sin Sufijo _interno)

## Generalidades del Estándar Canónico para Procedimientos Públicos

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, estructura del resultset unificado y flujo de control para **todos los Procedimientos Almacenados Públicos u Orquestadores** (aquellos sin el sufijo `_interno`) en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias (Modelo Canónico)
1. **Firma de Cabecera Sin Parámetros OUTPUT**:
   - Los procedimientos públicos/orquestadores NO llevan parámetros de salida (`OUTPUT`) en su firma de cabecera.
   - Todo parámetro de entrada de tipo `UNIQUEIDENTIFIER` (UUID) inicia obligatoriamente con el prefijo `id` (`@idTipoIdIdentificacion`, `@idGrupo`, `@idCorrelacion`, `@idEstudianteGrupo`, `@idGrupoSesion`, `@idEstadoAsistencia`, `@idEstudiante`, `@idSesion`).
2. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - Declaraciones con `DECLARE` ubicadas **exclusivamente en la cabecera: después del `AS` y antes del primer `BEGIN`**.
   - Inicialización de GUIDs por defecto utilizando `dbo.ufn_obtener_parametro_guid(@variable, 'GENERAL', 'GUID_DEFECTO_CORRELACION')`.
   - Limpieza de texto únicamente mediante `TRIM(@variable)`.
   - **PROHIBIDO EL USO DE `ISNULL` O `COALESCE`**.
   - Variables locales de respuesta inicializadas internamente:
     ```sql
     DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @estadoResultado BIT = 1;
     ```
3. **Flujo Lógico Estandarizado de Gestión de Entidades**:
   - Consultar si existe en la vista correspondiente (`uv_...`).
   - Si existe: validar estado activo y actualizar datos pertinentes.
   - Si no existe: invocar al procedimiento interno de sincronización/creación (`*_interno`).
4. **Estructura de Bloques y Documentación Paso a Paso**:
   - Inicio del cuerpo con `BEGIN SET NOCOUNT ON; BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH`.
   - Comentarios estructurados por pasos (`-- PASO 1: ...`, `-- PASO 2: ...`).
   - Todo `IF` lleva explícitamente `BEGIN` y `END`.
5. **Consumo Centralizado del Catálogo de Mensajes**:
   - Invocación a `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` al mensaje técnico.
   - Manejo de excepciones en bloque `CATCH` invocando `'SYS_001'` y capturando la traza mediante `dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto)`.
6. **Bloque Final Obligatorio de Retorno (Resultset Unificado)**:
   ```sql
   SELECT
       idCorrelacion           = @idCorrelacionDefecto,
       mensajeUsuarioResultado = @mensajeUsuarioResultado,
       mensajeTecnicoResultado = @mensajeTecnicoResultado,
       estadoResultado         = @estadoResultado;
   ```

---

## Catálogo de Procedimientos Públicos / Orquestadores (6 SPs)

---

### 1. `dbo.usp_registrar_estudiante_en_grupo_usuario_no_existente`
> **SUPERSEDED (LB-002.1C-A):** este SP fue eliminado de `schema/` en `daeac11` y no existe en la DB. El comando publico vigente es `dbo.usp_registrar_estudiante_en_grupo` con otra firma (sin `@idTipoIdIdentificacion`, con `@idUsuarioEjecutor`) y sin ownership transaccional. Contrato real y matriz de diferencias: `docs/work-items/LB-002.1C-A-db-contract-baseline-recovery/REPORT.md`. El texto siguiente es historico.

- **Caso de Uso de Negocio**: Orquestador principal de auto-registro e inscripción. Permite el registro completo de un estudiante en un grupo académico cuando el usuario no existe previamente en el sistema (o actualiza datos si ya existe), asegurando la creación del usuario, la asignación del perfil estudiante, la inscripción en el grupo y la vinculación al programa académico correspondiente.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`: ID del tipo de documento.
  - `@numeroIdentificacion INT`: Número de identificación.
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`: Correo electrónico del usuario.
  - `@password NVARCHAR(500)`: Contraseña.
  - `@idGrupo UNIQUEIDENTIFIER`: ID del grupo académico al que se inscribe.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`: ID de trazabilidad estandarizado.
  - `mensajeUsuarioResultado NVARCHAR(4000)`: Mensaje amigable para el cliente.
  - `mensajeTecnicoResultado NVARCHAR(4000)`: Traza técnica con ID de correlación.
  - `estadoResultado BIT`: Indica 1 para éxito y 0 para fallo.
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.uv_usuario`
  - `dbo.usp_validar_usuario_existe_por_id_interno`
  - `dbo.usp_sincronizar_usuario_interno`
  - `dbo.uv_estudiante_identidad`
  - `dbo.usp_sincronizar_estudiante_interno`
  - `dbo.usp_registrar_estudiante_en_grupo_interno`
  - `dbo.uv_grupo`, `dbo.uv_asignatura`, `dbo.uv_semestre_plan_estudio`, `dbo.uv_plan_estudio`
  - `dbo.usp_registrar_estudiante_en_programa_interno`
- **Códigos del Catálogo Consumidos**: `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO`, `SUC_REGISTRO_ESTUDIANTE_GRUPO`, `ERR_INESPERADO_REGISTRO_ESTUDIANTE` (`SYS_001`).

---

### 2. `dbo.usp_registrar_docente_en_grupo_usuario_no_existente`
- **Caso de Uso de Negocio**: Orquestador principal de gestión de docentes. Administra el registro de un docente y su asignación a un grupo académico. Verifica la existencia previa del usuario (actualizando biografía si existe o creándolo vía sincronización si no), habilita el perfil docente e inscribe al docente en el grupo deseado.
- **Parámetros de Entrada**:
  - `@idTipoIdIdentificacion UNIQUEIDENTIFIER`
  - `@numeroIdentificacion INT`
  - `@primerApellido NVARCHAR(255)` / `@segundoApellido NVARCHAR(255)`
  - `@primerNombre NVARCHAR(255)` / `@segundoNombre NVARCHAR(255)`
  - `@correo NVARCHAR(255)`
  - `@password NVARCHAR(500)`
  - `@idGrupo UNIQUEIDENTIFIER`
  - `@idCorrelacion UNIQUEIDENTIFIER`
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.uv_usuario`
  - `dbo.usp_validar_usuario_existe_por_id_interno`
  - `dbo.usp_sincronizar_usuario_interno`
  - `dbo.uv_docente_identidad`
  - `dbo.usp_sincronizar_docente_interno`
  - `dbo.usp_registrar_docente_en_grupo_interno`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

### 3. `dbo.usp_registrar_asistencia_estudiante`

> **ELIMINADO (2026-10-29):** este objeto se borró de `schema/` por no tener uso (migración `migrations/08_eliminar_codigo_sin_uso_up.sql`, work item `docs/work-items/BD-eliminar-codigo-sin-uso/`). El texto siguiente es histórico.
- **Caso de Uso de Negocio**: Orquestador de registro manual de asistencia por estudiante. Permite a los docentes o administradores registrar o actualizar el estado de asistencia de un estudiante matriculado para una sesión específica.
- **Parámetros de Entrada**:
  - `@idEstudianteGrupo UNIQUEIDENTIFIER`: ID de la matrícula del estudiante en el grupo.
  - `@idGrupoSesion UNIQUEIDENTIFIER`: ID de la sesión de clase.
  - `@idEstadoAsistencia UNIQUEIDENTIFIER`: ID del estado/razón causa de asistencia.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_estudiante_grupo_exista_interno`
  - `dbo.usp_validar_sesion_exista_por_id_interno`
  - `dbo.EstudianteGrupo`, `dbo.RazonCausa`
  - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

### 4. `dbo.usp_registrar_asistencia_estudiante_autonomo`
> **ELIMINADO (CULM-001 D.7, 2026-11-08):** este objeto se retiró de `schema/` (migración `migrations/26_culm001_d7_retiro_registro_autonomo_up.sql`, cierra TD-009 y retira `POST /api/v1/asistencias`). La asistencia se registra con `usp_registrar_asistencias_sesion` (lote), `usp_registrar_asistencias_toma` y `usp_registrar_asistencia_por_token` (B.2).

---

### 5. `dbo.usp_registrar_asistencias_sesion`
- **Caso de Uso de Negocio**: Orquestador de registro masivo de asistencias por lote JSON. Permite procesar en una sola transacción la lista completa de asistencias para todos los estudiantes matriculados en una sesión de clase.
- **Parámetros de Entrada**:
  - `@idSesion UNIQUEIDENTIFIER`: ID de la sesión de clase.
  - `@asistenciaJSON NVARCHAR(MAX)`: Carga útil en formato JSON con la lista de objetos `[{ "idEstudiante": "...", "estado": "AN|SJC|EX" }]`. **Estados públicos: `AN` (asistencia normal), `SJC` (sin justa causa), `EX` (excusa)**; se normalizan con `TRIM` + `UPPER`. `A`, `F`, `T`, `J`, `ABC`, vacío o ausente son inválidos (`RC_001`); no hay conversión `A → AN` / `F → SJC` en el batch.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
  - `@idUsuarioEjecutor UNIQUEIDENTIFIER = NULL`: **`Usuario.id`** del docente autenticado (no `Docente.id`). **Requerido semánticamente**: *opcional en firma ≠ opcional en contrato*. `NULL` u omitido → `estadoResultado = 0` (`GEN_002`, campo `idUsuarioEjecutor`), sin escrituras y sin saltarse RBAC/titularidad.
- **Resultset Devuelto** (una única fila, sin cambios):
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Seguridad**: RBAC perfil `DOCENTE` y titularidad de la sesión (`Sesion → Grupo → Docente.id → uv_docente_identidad → idUsuario = @idUsuarioEjecutor`).
- **Atomicidad**: el lote se valida completo antes de escribir; un fallo revierte todo el lote (transacción propia o `SAVE TRANSACTION` bajo transacción externa).
- **RazonCausa**: catálogo cerrado; ningún código desconocido crea filas en `dbo.RazonCausa`.
- **Lectura**: el estado se consulta vía `dbo.uv_detalle_asistencia.codigoRazonCausa` (y `dbo.uv_razon_causa.codigo`).
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_permiso_rbac_usuario_interno`
  - `dbo.usp_validar_sesion_exista_por_id_interno`
  - `dbo.usp_validar_titularidad_jerarquica_interno` (`SESION`)
  - `OPENJSON`
  - `dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno`
  - `dbo.usp_sincronizar_asistencia_estudiante_interno`
- **Códigos del Catálogo Consumidos**: `GEN_002`, `RC_001`, `SES_001`, `VAL_003`, `EST_004`, `GEN_004`, `SYS_001`.
- Detalle completo: [`docs/stored-procedures/usp_registrar_asistencias_sesion.md`](docs/stored-procedures/usp_registrar_asistencias_sesion.md).

---

### 6. `dbo.usp_generar_sesiones_grupo`
- **Caso de Uso de Negocio**: Orquestador masivo de planificación académica. Genera automáticamente el calendario de sesiones de clase recurrentes para un grupo a lo largo de todo su periodo académico, basándose en la configuración de franjas horarias y días de la semana.
- **Parámetros de Entrada**:
  - `@idGrupo UNIQUEIDENTIFIER`: ID del grupo académico.
  - `@idCorrelacion UNIQUEIDENTIFIER`: ID de correlación de trazabilidad.
- **Resultset Devuelto**:
  - `idCorrelacion UNIQUEIDENTIFIER`
  - `mensajeUsuarioResultado NVARCHAR(4000)`
  - `mensajeTecnicoResultado NVARCHAR(4000)`
  - `estadoResultado BIT`
- **Procedimientos Internos y Vistas Invocados**:
  - `dbo.usp_validar_id_correlacion_esta_presente_interno`
  - `dbo.usp_validar_grupo_exista_por_id_interno`
  - `dbo.usp_validar_horarios_grupo_interno`
  - `dbo.usp_validar_fechas_periodo_academico_interno`
  - `dbo.Grupo`, `dbo.PeriodoAcademico`, `dbo.Horario`, `dbo.Dia`, `dbo.Sesion`
- **Códigos del Catálogo Consumidos**: `GEN_004`, `SYS_001`.

---

## Verificación de Integridad y Despliegue

Todos los procedimientos listados en esta documentación han sido compilados y probados exitosamente en la base de datos `gestionasistenciadb` mediante la ejecución del script `deploy_schema.ps1`.

---

## Addendum CC-003G-01 — proveedores consumidos por el backend

Contrato completo, decisiones y limitaciones: `docs/work-items/CC-003G-01-public-user-plan-providers/CONTRACT.md`.

### 7. ~~`dbo.usp_sincronizar_usuario`~~ (RETIRADO, VAL ROL-05, 2026-11-12)
- **Estado**: retirado con la migracion `39_val_retiro_alta_usuarios_sin_ambito_up.sql` (decision de John). Era el alta generica de usuario base para `POST /api/v1/usuarios`, que cualquier usuario autenticado podia llamar sin ejecutor ni ambito; el backend retiro esa ruta y el SP quedo sin llamadores. Se retiraron el SP y su `GRANT EXECUTE` a `rol_asistencias_runtime`.
- **Lo que no cambia**: `dbo.usp_sincronizar_usuario_interno` sigue siendo el nucleo de los altas con ambito (`usp_crear_decano_interno`, `usp_crear_coordinador_interno`, `usp_vincular_docente_programa`, `usp_admitir_estudiante`, `usp_registrar_estudiante_en_grupo`, `usp_matricular_por_token_interno`) y sigue con `DENY EXECUTE` al runtime.
- **Prueba**: `test/test_val_retiro_alta_usuarios_sin_ambito.sql` (`VAL_ROL05_*`). El down de la migracion 39 recrea el SP y su permiso tal como estaban.

### 8. `dbo.usp_registrar_o_actualizar_plan_estudio`
- **Caso de uso**: alta/actualizacion del `inp` de un plan por el COORDINADOR titular del programa (`/api/v1/coordinador/planes-estudio`).
- **Parametros**: `@idPlanEstudio`, `@idPrograma`, `@inp`, `@idCorrelacion`, `@idUsuarioEjecutor` (obligatorio, fail-closed).
- **Flujo**: correlacion, RBAC `COORDINADOR`, titularidad `PROGRAMA`, validaciones de entrada, transaccion propia/savepoint con bloqueo de la fila del programa, upsert por id con unicidad (programa, inp).

---

## Addendum HU081-HU083 / HU096-HU098 / HU060-HU064 / HU104-HU145 (2026-10-25)

Work items: `docs/work-items/HU081-HU082-HU083-plan-estudio-estado-semestres/`, `HU096-HU097-HU098-periodos-academicos/`, `HU064-HU060-HU061-consultas-coordinador/` y `HU104-HU105-HU109-HU119-HU145-lecturas-decano/`. Mensajes en `schema/seed/17_mensajes_plan_estudio.sql` (`PLA_002`..`PLA_006`) y `schema/seed/17_mensajes_periodo_academico.sql` (`PER_001`..`PER_009`; `PER_008` y `PER_009` son la regla de periodo cerrado de VAL-pendientes-john PRU-15).

### Comandos (resultset canónico de 4 columnas, `@idUsuarioEjecutor` obligatorio)

| SP | Caso de uso | RBAC / ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_cambiar_estado_plan_estudio` | HU081 activar/inactivar el plan (`PlanEstudio.estado`) | `COORDINADOR` titular del programa | `PLA_002` |
| `dbo.usp_agregar_semestre_plan_estudio` | HU082 añadir el siguiente semestre (máx. 10) | `COORDINADOR` titular | `PLA_002`, `PLA_003` |
| `dbo.usp_quitar_semestre_plan_estudio` | HU083 quitar el último semestre sin asignaturas | `COORDINADOR` titular | `PLA_002`, `PLA_004`, `PLA_005`, `PLA_006` |
| `dbo.usp_crear_periodo_academico` (reescrito) | HU096 crear período (`codigo`/`anio` derivados de `fechaInicio`) | `ADMINISTRADOR` de institución activa | `PER_002`, `PER_003`, `PER_005` |
| `dbo.usp_actualizar_periodo_academico` | HU097 modificar nombre y fechas | `ADMINISTRADOR` | `PER_001`, `PER_002`, `PER_003`, `PER_005` |
| `dbo.usp_eliminar_periodo_academico` | HU098 eliminar si no tiene grupos | `ADMINISTRADOR` | `PER_001`, `PER_004`, `PER_005`, `PER_006` |

### Consultas (READ_QUERY_RESULTSET; fallas por `THROW`; `SESSION_CONTEXT` capturado y restaurado)

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_estudiantes_facultad_paginado` | HU104/HU105 directorio y búsqueda de estudiantes; al final del resultset `codigoTipoIdentificacion` (sigla del tipo de documento, MEJORAS-SERGIO-2026-11-18) | facultad del decano ejecutor (`uv_auth_estudiante`) | `VAL_001`, `PAG_001` |
| `dbo.usp_consultar_estudiante_facultad_detalle` | HU105 ficha (matrículas) del estudiante | facultad del decano | `VAL_001` |
| `dbo.usp_consultar_estructura_facultad` | HU109/HU119 Facultad → Programa → Plan | facultad del decano (`uv_auth_facultad`, `uv_auth_programa`) | `VAL_001` |
| `dbo.usp_consultar_sesiones_facultad_paginado` | HU145 cronograma de sesiones por rango | facultad del decano (`uv_auth_sesion`, `uv_auth_grupo`) | `VAL_001`, `PAG_001` |
| `dbo.usp_consultar_programas_creditos_facultad_paginado` | HU112 tabla unificada de programas y créditos (una fila por programa y plan con semestres, asignaturas y suma de créditos) | DECANO, su facultad (`uv_auth_programa` + `uv_decano`) | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_docentes_facultad_paginado` | HU128 directorio de docentes de la facultad filtrable por programa (vínculo `DocentePrograma` activo). HU136 (2026-11-05): también para el ADMINISTRADOR (docentes de toda su institución), filtro opcional `@idFacultad` y, solo para el administrador, `@estadoVinculo` (`ACTIVO` por defecto, `SIN_VINCULO` o `TODOS`: docentes retirados de todos sus programas). Columna nueva al final: `tieneVinculoActivo` | DECANO, su facultad (`uv_auth_docente_programa` + `uv_decano`); ADMINISTRADOR, las facultades de su institución (`uv_administrador`) | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_coordinadores_facultad_paginado` | CIERRE-W1B directorio paginado de coordinadores de la facultad del decano: una fila por coordinador con su primer programa, nombres separados, correo, estado y conteos de docentes y grupos; filtros `@busqueda` (nombre, documento, correo o programa), `@estaActivo` y `@sinPrograma` | DECANO, solo la facultad a su cargo (`uv_coordinador` + `uv_decano`); un decano sin facultad no ve filas | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_asignaturas_ambito_consolidado` | CIERRE-W2A opciones del filtro de materia del consolidado: asignaturas con grupos en el ámbito del ejecutor (`uv_auth_grupo`), opcionalmente de un período (`@idPeriodoAcademico`), por nombre, sin paginar | COORDINADOR su programa, DECANO su facultad, ADMINISTRADOR su institución | `VAL_001`, `SEC_001` |
| `dbo.usp_consultar_docentes_ambito_consolidado` | CIERRE-W2A opciones del filtro de docente del consolidado: docentes titulares con grupos en el ámbito del ejecutor, opcionalmente de un período, por nombre, sin paginar | COORDINADOR su programa, DECANO su facultad, ADMINISTRADOR su institución | `VAL_001`, `SEC_001` |
| `dbo.usp_consultar_resumen_materias_estudiante` | CIERRE-W2B indicadores del tablero del estudiante en una fila (`totalMaterias`, `materiasEnRiesgo`, `totalHorasFalta`, `totalCreditos`) sobre las mismas materias que `usp_consultar_materias_estudiante` (ambos leen `uv_materia_estudiante` con `MATRICULA/ESTADO_INSCRITA`); en riesgo = `codigoPermanencia` RIESGO o PERDIDA de `uv_resumen_asistencia_estudiante_grupo` (umbrales del catálogo, NULL si no hay umbrales) | ESTUDIANTE, solo sus matrículas | `GEN_002`, `SEC_001` |
| `dbo.usp_consultar_sesiones_materia_estudiante` | CIERRE-W2B orden determinista `fechaHoraInicio, numero, id` y filtro opcional `@idGrupo` (NULL = todos los grupos inscritos de la asignatura; un grupo ajeno devuelve 0 filas); firma por defecto compatible | ESTUDIANTE, solo sus matrículas inscritas | `GEN_002`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado` | CIERRE-W3M matriz estudiantes x sesiones del grupo ya cruzada: pagina de matriculas (`@busqueda` por nombre o documento) con el estado de cada celda de `uv_asistencia_sesion_horas` (DEC-066) y minutos asistidos | DOCENTE titular del grupo | `GEN_002`, `SEC_001`, `PAG_001`, `ERR_GRUPO_NO_EXISTE`, `SEC_002` |
| `dbo.usp_consultar_resumen_sesiones_grupo_docente` | CIERRE-W3M resumen de sesiones del grupo: estado temporal (PROGRAMADA, EN_CURSO, EJECUTADA, CANCELADA), conteos por sesion y del grupo, sesion en curso/proxima, estudiantes en riesgo y promedio con umbrales de catalogo | DOCENTE titular del grupo | `GEN_002`, `SEC_001`, `ERR_GRUPO_NO_EXISTE`, `SEC_002` |
| `dbo.usp_consultar_resumen_grupos_docente` | CIERRE-W3I totales de los grupos del docente titular (una fila): grupos habilitados (periodo vigente hoy), estudiantes activos, cupo total y tasa de ocupacion (NULL con cupo 0) | DOCENTE: solo sus grupos | `VAL_001`, `SEC_001` |
| `dbo.usp_consultar_kpis_coordinador` / `_decano` / `_institucion` (CIERRE-W3I) | Columnas nuevas al final: coordinador `totalDocentes`, `gruposActivos`, `cupoTotal`, `matriculadosActivos`, `tasaAforo`, `estudiantesRegistrados`; decano `totalCoordinadores`, `totalDocentes`; institucion `totalDecanos`, `decanosActivos`, `facultadesActivas` | sin cambio | sin cambio |
| `dbo.usp_consultar_consolidado_asistencia_grupos_paginado`, `usp_consultar_revisiones_cancelacion_{coordinador,decano,docente}_paginado`, `usp_consultar_alertas_estudiante` (CIERRE-W3I) | Columna nueva al final con el nivel de permanencia (`codigoPermanencia` en el consolidado; `codigoPermanenciaActual` en revisiones y alertas) calculado con `ufn_clasificar_permanencia` y los umbrales del catalogo | sin cambio | sin cambio |
| `dbo.usp_buscar_asignaturas_paginado` | HU143 búsqueda transversal de asignaturas por código o nombre | ADMINISTRADOR: todas las facultades de su institución; DECANO: solo su facultad (`uv_auth_programa` + `uv_administrador`/`uv_decano`) | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_buscar_estudiantes_institucion_paginado` | HU157 buscador de estudiantes del administrador | ADMINISTRADOR, su institución (`uv_auth_estudiante` + `uv_administrador`) | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_historial_estudiante` | HU157 ficha unificada: datos, programas, grupos por período y resumen de asistencia | ADMINISTRADOR (institución) o DECANO (su facultad) vía `uv_auth_estudiante` | `VAL_001`, `SEC_001` |
| `dbo.usp_consultar_consolidado_asistencia_grupos_paginado` | HU061 consolidado por cohorte (período académico), asignatura y docente: una fila por grupo con activos, sesiones ejecutadas, asistencias, faltas, excusas, % de asistencia e inasistencia, riesgo y pérdida | COORDINADOR (programa), DECANO (facultad) o ADMINISTRADOR (institución) vía `uv_auth_grupo` | `VAL_001`, `SEC_001`, `PAG_001` |
| `dbo.usp_consultar_auditoria_eventos_paginado` | HU172 rastro de auditoría (quién, cuándo, acción, recurso, resultado) por rango UTC; por defecto solo acciones de asistencia (`uv_auditoria_evento.esAccionAsistencia`) | solo ADMINISTRADOR | `VAL_001`, `SEC_001`, `PAG_001`, `GEN_002` |
| `dbo.usp_consultar_componentes_formacion` | HU147 componentes de formación (BAS, INS, ESP) con su número de asignaturas | ADMINISTRADOR, DECANO o COORDINADOR | `VAL_001`, `SEC_001` |
| `dbo.usp_guardar_tipo_identificacion` | **ELIMINADO (2026-11-04)**: TipoIdentificacion es de solo consulta (migración 11). Histórico: HU153 crear tipo de documento (código 1-5 letras único, nombre 3-50 único) o editar solo su nombre; salida canónica de 4 columnas (comando) | solo ADMINISTRADOR | `GEN_002`, `SEC_001`, `GEN_001`, `GEN_003`, `GEN_004`/`GEN_005` |

HU064/HU060/HU061 consumen los SP existentes `usp_consultar_grupos_paginado`, `usp_consultar_sesiones_grupo_paginado` y `usp_consultar_asistencias_sesion_paginado` (sin cambios; ámbito por programa vía `uv_auth_grupo`/`uv_auth_sesion`).

Permisos aditivos: `schema/security/rol_asistencias_runtime_hu081_hu083.sql`, `_hu096_hu098.sql`, `_hu060_hu064.sql`, `_hu104_hu145.sql` y `_hu112_hu157.sql`. Pruebas: `test/test_usp_plan_estudio_estado_semestres.sql`, `test/test_usp_periodo_academico_gestion.sql`, `test/test_consultas_coordinador_programa.sql` `test/test_consultas_decano_facultad.sql` y `test/test_consultas_transversales_hu112_hu157.sql`, registradas en `test_suite.sql`. Las consultas paginadas de HU112/HU128/HU143/HU157 validan correlación, ejecutor, perfil (RBAC) y paginación con `usp_validar_consulta_paginada_interno`, que también fija el `SESSION_CONTEXT`.

## Addendum HU010/HU011 — consulta de solicitudes de revisión del estudiante (2026-10-26)

Work item: `docs/work-items/HU010-HU011-consulta-reclamos-estudiante/` (contrato HTTP en el work item homónimo del backend).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_solicitudes_revision_estudiante` | HU010/HU011 "Mis Reclamos": solicitudes propias con estado, respuesta del docente y soporte vinculado; READ_QUERY_RESULTSET + `totalRegistros`, paginación acotada (1..100, sin `PAG_001`) | ownership en tablas base: `SolicitudRevisionAsistencia → Asistencia → EstudianteGrupo → Estudiante.usuario = @idUsuarioEjecutor` | `VAL_001` |

Parámetros: `@idUsuarioEjecutor`, `@idCorrelacion`, `@codigoEstado` (P/A/R, opcional), `@numeroPagina`, `@tamanoPagina`. Resultset con las mismas columnas y tipos que `usp_consultar_solicitudes_revision_docente` (LB-004D, R2); el soporte se resuelve con el parámetro `ARCHIVO.ESTADO_ADJUNTO`. Permiso aditivo: `schema/security/rol_asistencias_runtime_hu010_hu011.sql`. Prueba: `test/test_consultas_reclamos_estudiante.sql` (E-01..E-08). Sin cambios de tablas ni de objetos congelados.

## Addendum HU051 — retiro de un estudiante del grupo por el docente titular (2026-10-27)

Work item: `docs/work-items/HU051-retirar-estudiante-grupo/` (contrato HTTP en el work item homónimo del backend).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_retirar_estudiante_grupo` | Comando (resultset canónico): matrícula activa → `I` (inactivo), auditoría `RETIRO_ESTUDIANTE_GRUPO` con el motivo en `AuditoriaEvento.metadata`; asistencias intactas; cupo liberado | docente titular (`Grupo.docente → Docente.usuario`) | `GEN_002`, `RET_001` grupo inexistente o ajeno, `RET_002` sin matrícula activa, `RET_003` período terminado (fecha local `TIEMPO.ZONA_HORARIA_SQLSERVER`), `RET_004` motivo 1..500, `RET_005` éxito |
| `dbo.usp_consultar_destinatarios_retiro_estudiante_grupo` | Lectura: ESTUDIANTE, DOCENTE y COORDINADOR del programa con nombre, correo y contexto del grupo para el aviso | docente titular (otro ejecutor ⇒ 0 filas) | `VAL_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu051.sql`. Mensajes: `schema/seed/21_mensajes_retiro_estudiante_grupo.sql`. Prueba: `test/test_usp_retirar_estudiante_grupo.sql` (R-01..R-09). Sin cambios de tablas ni de objetos congelados.

## Addendum HU159 — corrección de identidad de usuarios por jerarquía (2026-11-05)

Work item: `docs/work-items/HU159-correccion-identidad-usuarios/` (contrato HTTP en el work item homónimo del backend). Decisión de John (2026-11-05): cada nivel corrige al de abajo los nombres, apellidos y el tipo y número de documento. El administrador corrige al decano, el decano al coordinador (HU121), el coordinador al docente vinculado a su programa (HU092) y al estudiante de su programa. El administrador no se corrige por la app y no gestiona estudiantes (`HOJA_DE_RUTA_JERARQUIA_ROLES.md` del repositorio Infra; HU160 descartada).

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_corregir_identidad_usuario` | Comando (resultset canónico + `idUsuario`, `correo`, `numeroIdentificacion`). `@tipoUsuario` = `ESTUDIANTE` o `DECANO`. Corrige nombres, apellidos y documento; no toca correo, contraseña ni estado; motivo obligatorio siempre; auditoría `CORREGIR_IDENTIDAD_ESTUDIANTE` / `CORREGIR_IDENTIDAD_DECANO` | ESTUDIANTE: COORDINADOR de un programa del estudiante (`EstudiantePrograma → Programa.coordinador`). DECANO: ADMINISTRADOR de la institución de sus facultades. Fuera del ámbito = `GEN_001` (no revela la existencia) | `GEN_002`, `GEN_001`, `SEC_001`, `IDE_001` motivo 1..500, `VAL_001`/`VAL_003`/`VAL_004`, `ERR_UNICIDAD_DOCUMENTO`, `IDE_003` documento apagado, `IDE_002` éxito |
| `dbo.usp_actualizar_coordinador` (HU121, aditivo) | Acepta `@idTipoIdIdentificacion`, `@numeroIdentificacion` y `@motivo` opcionales (NULL = el documento no cambia). Si cambia: motivo obligatorio y auditoría `CORREGIR_DOCUMENTO_COORDINADOR` | Igual que antes (DECANO titular de la facultad) | `IDE_001`, `IDE_003`, `ERR_UNICIDAD_DOCUMENTO` además de los existentes |
| `dbo.usp_actualizar_docente_programa` (HU092, aditivo) | Igual que HU121; auditoría `CORREGIR_DOCUMENTO_DOCENTE`. El documento cuenta como "campo a actualizar" | Igual que antes (COORDINADOR titular del programa) | `IDE_001`, `IDE_003`, `ERR_UNICIDAD_DOCUMENTO` además de los existentes |

Internos (sin permisos; encadenamiento de propietario):

- `usp_corregir_documento_usuario_interno`: único punto que cambia el documento. Lee `IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO` (1 por defecto; distinto de 1 ⇒ `IDE_003`), exige motivo si el documento cambia, valida tipo, número y unicidad excluyendo al propio usuario. Con `@soloValidar = 1` valida sin escribir: las fachadas lo llaman antes de cualquier escritura, así un rechazo no necesita `ROLLBACK`. Aislado para poder apagarlo por parámetro o retirarlo sin tocar la corrección de nombres.
- `usp_corregir_identidad_usuario_interno`: núcleo de estudiante y decano (valida el documento, actualiza nombres con `usp_actualizar_datos_usuario_interno` conservando el correo, aplica el documento y audita).
- `usp_registrar_auditoria_identidad_interno`: fila de `AuditoriaEvento` con `metadata` = `{ idUsuario, motivo, anterior, nuevo }` (instantáneas de `ufn_obtener_identidad_usuario_json`).

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu159.sql`. Mensajes: `schema/seed/31_mensajes_correccion_identidad.sql` (`IDE_001`..`IDE_003`). Parámetro: `schema/seed/32_parametros_identidad.sql`. Prueba: `test/test_usp_corregir_identidad_usuario.sql` (9 marcadores críticos, incluidos el parámetro en 0 y en 1). Sin cambios de tablas ni de objetos congelados.

## Addendum HU053/HU054/HU055 — solicitudes de ingreso a un grupo (2026-10-27) — RETIRADO en CULM-001 A

Retirado en CULM-001 A.1 (decision del responsable, 2026-11-06: HU026, HU053, HU054 y HU055 descartadas). La tabla
`SolicitudIngresoGrupo`, sus 6 SP, sus grants, los estados `E` (en espera) y los mensajes `SIG_*` se eliminan con
`migrations/13_culm001_a_retiro_solicitudes_up.sql`, que antes archiva el historial en `dbo.zz_archivo_*` (DEC-010).
El estado `X` (retirada) de `dbo.Estado` se conserva (seed `33_culm001_a_catalogos.sql`) para el reclamo retirado.

## Addendum HU006 — perfil del usuario autenticado (2026-10-27)

Work item: `docs/work-items/HU006-perfil-usuario/` (contrato HTTP en el work item homónimo del backend). Solo lectura; sin tablas nuevas.

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_perfil_usuario` | Lectura: datos personales (de `uv_usuario`, sin contraseña) y una fila por vínculo: ESTUDIANTE→programa, DOCENTE→programa (facultad del programa; sin tipo de vinculación desde la migración 56), COORDINADOR→programa, DECANO→facultad, ADMINISTRADOR→institución; sin vínculos devuelve 1 fila con el vínculo en NULL | solo el usuario ejecutor (no recibe otro id) | `VAL_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu006.sql`. Prueba: `test/test_usp_consultar_perfil_usuario.sql` (P-01..P-03).

## Addendum HU094/HU095 — ficha del docente y consolidado del directorio docente del coordinador (2026-10-27)

Work item: `docs/work-items/HU094-HU095-directorio-docentes-coordinador/` (contrato HTTP en el work item homónimo del backend). Solo lectura; sin cambios de tablas.

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_historial_grupos_docente_programa` | Lectura paginada (HU094): grupos del docente en el programa del coordinador, todos los períodos (filtro opcional), con `estadoPeriodo` VIGENTE/FINALIZADO/PROXIMO (fecha local) y columnas `resumen*` de todo el historial + `totalRegistros` | programa del coordinador ejecutor (`usp_resolver_programa_coordinador_interno`); el docente debe tener vínculo (activo o inactivo) con ese programa | `VAL_001`, `KPI_001`, `GEN_001` (THROW) |
| `dbo.usp_consultar_resumen_docentes_programa` | Lectura (HU095): UNA fila con los vínculos activos e inactivos del programa (criterio `uv_docente_programa.estaActivoDocentePrograma`); sin agrupar por tipo de vinculación (retirado en la migración 56) | programa del coordinador ejecutor | `VAL_001`, `KPI_001` (THROW) |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu094_hu095.sql`. Pruebas: `test/test_usp_consultar_historial_grupos_docente_programa.sql` (H-01..H-06) y `test/test_usp_consultar_resumen_docentes_programa.sql` (R-01..R-03).

## Addendum HU008 — oferta de grupos del estudiante y regla de inscripción en el programa (2026-10-27)

Work item: `docs/work-items/HU008-oferta-grupos-estudiante/` (contrato HTTP en el work item homónimo del backend). Sin tablas nuevas.

| Objeto | Cambio | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_oferta_grupos_estudiante` | Lectura paginada nueva: grupos ESP de los programas del estudiante y, si `OFERTA.INCLUIR_TRANSVERSALES = 1`, BAS/INS de su institución, en períodos vigentes/próximos; docente, horario, cupos, `matriculado`, solicitud abierta y `codigoComponente` | estudiante ejecutor (`Estudiante.usuario`; otro rol = 0 filas) | `VAL_001` (THROW) |
| `dbo.usp_registrar_estudiante_en_grupo_interno` / `_autonomo` | Regla de John: solo una asignatura **ESP** crea `EstudiantePrograma`; BAS/INS matriculan sin inscribir en el programa (JOIN a `Componente` con `codigo = 'ESP'`) | sin cambio | sin cambio |
| `CatalogoParametro` `OFERTA.INCLUIR_TRANSVERSALES` | Parámetro nuevo (1 por defecto). `UPDATE ... SET valor = '0'` oculta las transversales de la oferta (solo enlace del docente) | — | — |

Permiso aditivo: `schema/security/rol_asistencias_runtime_hu008.sql`. Seed: `24_parametro_oferta_grupos.sql`. Pruebas: `test/test_usp_consultar_oferta_grupos_estudiante.sql` (O-01..O-05) y `test/test_hu008_regla_inscripcion_programa.sql` (RI-01..RI-03).

## Addendum INT-HU-01 — reactivación de la matrícula retirada al aceptar una solicitud de ingreso (2026-10-28)

> CULM-001 A.1 (DEC-009): la regla se mueve a `dbo.usp_reactivar_matricula_retirada_interno`, que llama
> `usp_registrar_estudiante_en_grupo_interno` (matricula manual HU050 y QR/PIN HU176B). Ver el addendum CULM-001 A.

`dbo.usp_resolver_solicitud_ingreso_grupo`, ACEPTAR con cupo: si el estudiante tiene una matrícula `I` (retirado, HU051) en el grupo, se reactiva (`I` → `A`), se enlaza en la solicitud y responde `SIG_011` (antes: 409 por duplicado desde la matrícula interna). Sin cambios de firma, resultset ni mensajes. Work item: `docs/work-items/INT-HU-01-reactivar-matricula-retirada/`. Prueba: `test/test_int_hu01_reactivar_matricula_retirada.sql` (RM-01..RM-03).

---

## Addendum REC5 (2026-10-29): índice de SP públicos sin ficha en este documento

La auditoría BD 2026-10-28 encontró 48 SP públicos sin ficha aquí; 10 de ellos (los paginados y por id legacy) se eliminaron el 2026-10-29 por no tener uso, así que el índice lista 38. El endpoint y el rol de cada uno están en `especificacion_sp_endpoints.md` (Addendum REC5). El detalle de reglas y códigos, en el work item de su HU. Propósito tomado del comentario de cabecera del SP.

| SP | Parámetros | Propósito |
|---|---|---|
| `usp_actualizar_coordinador` | `@idCoordinador, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor, @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @motivo = NULL` | HU121: edita nombres, apellidos y correo de un coordinador de la facultad del decano ejecutor. Fachada transaccional: valida RBAC y titularidad, y delega la escritura en usp_actualizar_datos_usuario_interno. HU159 (2026-11-05): también corrige el tipo y el número de documento con `usp_corregir_documento_usuario_interno` (opcional; si cambia, motivo obligatorio y auditoría `CORREGIR_DOCUMENTO_COORDINADOR`). Devuelve idUsuario para que el backend sincronice la cuenta (y el username) |
| `usp_actualizar_docente_programa` | `@idDocente, @idPrograma, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @idCorrelacion, @idUsuarioEjecutor` | HU092: edita los nombres/apellidos de la persona (el tipo de vinculacion se retiro en la migracion 56). Solo se actualizan los parametros no nulos (''/vacio en un segundo nombre o apellido lo limpia). Correo y documento NO se editan aqui (el correo exi… |
| `usp_actualizar_facultad` | `@id, @nombre, @idDecano, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_facultad] Historias de Usuario: HU110 (modificar denominacion) y HU117 (reasignar decano) Ambito: Administrador Institucional (Nivel 1 de custodia jerarquica) Semantica: un parametro NULL no se modifica. Al menos uno es obl… |
| `usp_actualizar_programa_academico` | `@idPrograma, @nombre, @idTipoPrograma, @idCoordinador, @idModalidad, @idJornada, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_actualizar_programa_academico] Historia de Usuario: HU077 Ambito: Decano de Facultad. Edicion de nombre, tipo, modalidad, jornada y coordinador de un programa de la facultad del decano. Salida Canonica: (idCorrelacion, mensajeUsuarioR… |
| `usp_actualizar_sesion_v2` | `@idSesion, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: actualizacion v2 (PATCH de reemplazo completo de horas). El backend solo invoca este SP con instantes normalizados a UTC desde RFC3339 con offset explicito (UTC-D02): horas y marca UTC_V2 se escriben en el MISMO UPDATE. Mismos parametros n… |
| `usp_cambiar_estado_coordinador` | `@idCoordinador, @estaActivo, @idFacultad, @idCorrelacion, @idUsuarioEjecutor` | HU122: activa o desactiva el rol de coordinador de la facultad del decano ejecutor. Regla D3: no se puede desactivar a quien coordina un programa activo (COO_001). Regla D1: Usuario.estado pasa a 0 solo si la persona no conserva otro rol activo; al reactivar v… |
| `usp_cambiar_estado_docente_programa` | `@idDocente, @idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | HU093 (D12): activa o inactiva el VINCULO del docente con el programa del coordinador (DocentePrograma.estado). No toca Usuario.estado, ni el rol Docente, ni los grupos ya asignados, ni la cuenta de identidad. Idempotente. RBAC COORDINADOR + titularidad PROGRA… |
| `usp_cambiar_estado_facultad` | `@id, @estaActiva, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_facultad] Historia de Usuario: HU111 (alternar estado operativo de la facultad) Ambito: Administrador Institucional. Recibe el estado deseado (idempotente), sin cascada. Salida Canonica: (idCorrelacion, mensajeUsuarioRe… |
| `usp_cambiar_estado_programa_academico` | `@idPrograma, @estaActivo, @idCorrelacion, @idUsuarioEjecutor` | Procedimiento: [dbo].[usp_cambiar_estado_programa_academico] Historia de Usuario: HU078 Ambito: Decano de Facultad. Activa o desactiva un programa de la facultad del decano. Recibe el estado destino (idempotente). Salida Canonica: (idCorrelacion, mensajeUsuari… |
| `usp_clasificar_procedencia_sesion` | `@idSesion, @ambiente, @idManifiesto, @hashEvidencia, @fechaHoraInicioVerificada, @fechaHoraFinVerificada, @fechaHoraInicioUtc, @fechaHoraFinUtc, @idUsuarioAprobador, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: UNICO camino administrativo para marcar una sesion historica como UTC_OWNER. No es un endpoint del backend: lo ejecuta el owner funcional/DBA con un manifiesto aprobado, sesion por sesion y ambiente por ambiente. Fail-closed: * el ejecutor… |
| `usp_consultar_aforo_grupos_facultad` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @idPrograma, @soloHabilitados` | usp_consultar_aforo_grupos_facultad (HU144). READ_QUERY_RESULTSET paginado. Solo lectura. Aforo = matriculados activos / cupo maximo (D4); NULL si el cupo es 0. No se recorta por encima de 100 %. @soloHabilitados = 1 (defecto) lista solo grupos habilitados en … |
| `usp_consultar_alerta_temprana_programa` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @idPeriodoAcademico, @semaforo, @filtroTexto` | usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura. Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6). |
| `usp_consultar_archivo_soporte_autorizado` | `@idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_consultar_archivo_soporte_autorizado  (LB-004D, R1) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: … |
| `usp_consultar_bitacora_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @numeroPagina, @tamanoPagina, @idPeriodoAcademico` | usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura. Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero. asistio = NULL cuando la sesion vencida… |
| `usp_consultar_candidatos_docente_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idPrograma, @busqueda` | usp_consultar_candidatos_docente_programa (HU091, picker de docentes existentes) Resultset: READ_QUERY_RESULTSET con datos MINIMOS (D4, sin correo): idDocente, idUsuario, codigoTipoIdentificacion, numeroIdentificacion, nombreCompleto. Candidato = docente activ… |
| `usp_consultar_comparativa_facultades` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura. Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion. Orden: ausentismo descendente (NULL al fina… |
| `usp_consultar_comparativa_programas_facultad` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura. Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano. Orden: ausentismo descendente (NULL al… |
| `usp_consultar_detalle_solicitud_revision_docente` | `@idSolicitud, @idUsuarioEjecutor, @idCorrelacion` | usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036) Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solici… |
| `usp_consultar_docentes_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idPrograma, @numeroPagina, @tamanoPagina, @busqueda, @estaActivo, @idDocente, @idUsuario` | usp_consultar_docentes_programa (HU062 / HU089 / HU063) Resultset: READ_QUERY_RESULTSET (filas de uv_auth_docente_programa + totalRegistros). NO es un MUTATION_COMMAND_RESULTSET. Las fallas de RBAC/titularidad se propagan con THROW (mensaje tecnico de catalogo… |
| `usp_consultar_ficha_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante` | usp_consultar_ficha_estudiante_programa (HU069). READ_QUERY_RESULTSET (1 fila). Solo campos que existen en la DB (sin telefono, D5). |
| `usp_consultar_kpis_coordinador` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_coordinador (HU065, HU070). READ_QUERY_RESULTSET (1 fila). Solo lectura: sin XACT_ABORT. Ambito: el programa que coordina el ejecutor. Todas las cifras salen de las vistas de resumen (ver CONTRACT §1). |
| `usp_consultar_kpis_decano` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura. Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3). Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / se… |
| `usp_consultar_kpis_institucion` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico` | usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura. Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por matricula activa (sesionesEjec… |
| `usp_consultar_programas_academicos` | `@idUsuarioEjecutor, @idCorrelacion, @numeroPagina, @tamanoPagina, @nombre, @estaActivo, @idTipoPrograma` | usp_consultar_programas_academicos (HU108, solo listado de programas) Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001). Ambito: las… |
| `usp_consultar_resumen_asistencia_estudiante_programa` | `@idUsuarioEjecutor, @idCorrelacion, @idEstudiante, @idPeriodoAcademico` | usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura. |
| `usp_consultar_tendencia_ausentismo` | `@idUsuarioEjecutor, @idCorrelacion, @idPeriodoAcademico, @granularidad` | usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura. Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) de… |
| `usp_crear_sesion_v2` | `@idGrupo, @nombre, @fechaHoraInicio, @fechaHoraFin, @idCorrelacion, @idUsuarioEjecutor` | UTC-D06-POST-FREEZE: creacion v2. El backend solo invoca este SP despues de normalizar un RFC3339 con offset explicito (perfil UTC-D02) al instante UTC, por lo que las horas recibidas son instantes UTC confirmados: se marcan UTC_V2 en el MISMO INSERT (usp_crea… |
| `usp_radicar_solicitud_revision_asistencia_v2` | `@idEstudiante, @idSesion, @categoria, @justificacion, @idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor` | usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2) Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta. * Sin @soporteNombre/@soporteUrl: la v2 no c… |
| `usp_registrar_archivo_soporte` | `@idArchivoSoporte, @nombreOriginal, @tipoContenido, @tamanioBytes, @checksumSha256, @idCorrelacion, @idUsuarioEjecutor` | usp_registrar_archivo_soporte  (LB-004D, W1) Registra en estado DRAFT la metadata de un soporte ya almacenado por el backend. El propietario es SIEMPRE @idUsuarioEjecutor (no existe parametro de propietario). El fileId lo genera el backend; la DB no lo genera … |
| `usp_revocar_identidad_externa` | `@emisor, @sujeto, @idCorrelacion` | SEC-BASELINE-017: revoca el vinculo (emisor, sujeto) -> Usuario.id. Idempotente: revocar un vinculo ya revocado responde exito sin cambios. La fila se conserva (estado = 0) para que la identidad revocada no pueda reutilizarse ni reasignarse a otra cuenta sin u… |
| `usp_vincular_docente_programa` | `@idDocente, @idUsuario, @idTipoIdentificacion, @numeroIdentificacion, @primerNombre, @segundoNombre, @primerApellido, @segundoApellido, @correo, @password, @idPrograma, @idCorrelacion, @idUsuarioEjecutor` | HU091: vincula un docente al programa del coordinador. Tres modos excluyentes: (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion) (b) @idUsuario        usuario existente que aun no es docente (c) datos de persona  alta nu… |
| `usp_vincular_identidad_externa` | `@emisor, @sujeto, @idUsuario, @correoVinculacion, @idCorrelacion` | SEC-BASELINE-017: registra el vinculo estable (emisor, sujeto) -> Usuario.id. Reglas (todas atomicas bajo UPDLOCK/HOLDLOCK; los indices unicos son la ultima barrera ante carreras): * El usuario debe existir y estar activo. * Repetir el mismo vinculo vigente es… |

## Addendum F1 — horario semanal del grupo (2026-10-30)

### `dbo.usp_consultar_oferta_creacion_grupo_docente`
- **Caso de uso (F3):** alimenta el formulario "Nuevo grupo" del docente: devuelve su propio `idDocente` y las asignaturas activas (de planes activos) de los programas con los que tiene vínculo activo. No expone nada fuera de esos programas. SES-GEN-01 exige que el cliente envíe `idPeriodoAcademico` explícito al crear el grupo; el SP no elige el más reciente.
- **Parámetros:** `@idUsuarioEjecutor`, `@idCorrelacion`.
- **Resultset:** `READ_QUERY_RESULTSET` (una fila por asignatura: `idDocente`, `idAsignatura`, `codigoAsignatura`, `nombreAsignatura`, `idPrograma`, `nombrePrograma`). Un ejecutor ausente (`GEN_002`) o que no es DOCENTE (`SEC_001`) se rechaza con `THROW` y el código de catálogo.
- **Permiso:** `GRANT EXECUTE` al runtime en `schema/security/rol_asistencias_runtime_f3_docente_crea_grupo.sql`.
- **Pruebas:** `test/test_usp_consultar_oferta_creacion_grupo_docente.sql`. Work item: `docs/work-items/F3-docente-crea-grupo/`.

---

### `dbo.usp_precargar_sesiones_grupo`
- **Caso de uso (F2):** alinea las sesiones **futuras** del grupo con su horario: crea las que faltan y retira las generadas que ya no encajan. El backend lo invoca en la misma transacción que crea el grupo y guarda el horario (y al cambiar el horario). No sustituye a `usp_generar_sesiones_grupo` (congelado, solo docente titular, genera desde el inicio del período); no lo modifica ni lo invoca.
- **Parámetros:** `@idGrupo`, `@idCorrelacion`, `@idUsuarioEjecutor`.
- **Quién:** el COORDINADOR del programa de la asignatura del grupo, o el DOCENTE titular del grupo (`SEC_002` en otro caso, sin cambios); cualquier otro perfil recibe `SEC_001`. Lo valida `usp_validar_gestion_grupo_coordinador_o_titular_interno`, compartido con `usp_guardar_horarios_grupo`.
- **Reglas:**
  - el grupo debe tener horario (`usp_validar_horarios_grupo_interno`) y su período, fechas coherentes (`usp_validar_fechas_periodo_academico_interno`);
  - solo se generan sesiones desde hoy (hora institucional) o desde el inicio del período si aún no empieza, hasta el fin del período; el pasado no se genera ni se toca;
  - no duplica: una sesión del mismo grupo, inicio y fin ya existente se respeta (idempotente);
  - se retiran las sesiones futuras con `procedenciaTemporal = UTC_GENERADOR` que ya no encajan en el horario y no tienen asistencia ni clasificación; las creadas a mano (`UTC_V2`) nunca se borran;
  - una hora local inexistente por cambio de horario de verano aborta antes de escribir (`SES_005`).
- **Escritura:** la hace `usp_precargar_sesiones_grupo_interno`; este SP controla la transacción (propia, o savepoint si ya hay una abierta) sin `XACT_ABORT ON`. El runtime solo tiene `EXECUTE` sobre el SP público (`rol_asistencias_runtime_f2_precarga_sesiones.sql`).
- **Resultset:** canónico de 4 columnas (`GEN_005` en éxito; el mensaje técnico trae las sesiones creadas y eliminadas).
- **Pruebas:** `test/test_usp_precargar_sesiones_grupo.sql`. Work item: `docs/work-items/F2-precarga-sesiones/`.

---

### `dbo.usp_guardar_horarios_grupo`
- **Caso de uso:** el COORDINADOR del programa define o reemplaza el horario semanal de un grupo (varias franjas). El backend lo invoca en la misma transacción que `usp_crear_grupo` y `usp_actualizar_grupo` cuando el comando trae `franjas`.
- **Parámetros:** `@idGrupo`, `@horariosJSON` (arreglo no vacío de `{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}` con códigos de `dbo.Dia`), `@idCorrelacion`, `@idUsuarioEjecutor`.
- **Reglas:**
  - formato, día existente y `horaFin > horaInicio` (`HOR_004`);
  - las franjas del grupo no se traslapan entre sí; las contiguas sí se permiten (`HOR_003`);
  - el docente titular no tiene otro grupo a la misma hora en el período (`HOR_002`, vía `usp_validar_cruce_horario_docente_interno`);
  - ejecutor COORDINADOR: el grupo debe pertenecer al programa que coordina (`SEC_002`);
  - ejecutor DOCENTE (F3): solo el titular del grupo (`SEC_002` si no lo es) y solo para definir el horario inicial; si el grupo ya tiene horario recibe `HOR_005` (los cambios posteriores los hace el coordinador);
  - cualquier otro perfil recibe `SEC_001`.
- **Escritura:** la hace `usp_guardar_horarios_grupo_interno` (`DELETE` + `INSERT` sobre `dbo.Horario`); este SP controla la transacción: propia, o savepoint si ya hay una abierta, sin `XACT_ABORT ON`. Un rechazo después de escribir deshace todo lo escrito. El runtime solo tiene `EXECUTE` sobre el SP público (`DENY` sobre el interno) y no puede escribir `dbo.Horario` directamente (`rol_asistencias_runtime_f1_horario_grupo.sql`).
- **Resultset:** canónico de 4 columnas (`GEN_005` en éxito).
- **Pruebas:** `test/test_usp_guardar_horarios_grupo.sql`. Work item: `docs/work-items/F1-horario-grupo/`.

---

### `dbo.usp_previsualizar_horario_grupo`
- **Caso de uso (SES-GEN-01):** previsualiza el calendario de sesiones y los conflictos del horario semanal, para un grupo nuevo o existente. Solo lectura; no escribe ni abre una transacción. El backend todavía no tiene un endpoint asociado.
- **Parámetros:** `@idGrupo` opcional; `@idAsignatura`, `@idPeriodoAcademico`, `@idDocente` para grupo nuevo (con grupo existente se toman del grupo; los cambios de asignatura o periodo se rechazan); `@horariosJSON` (arreglo no vacío de franjas); `@idCorrelacion`, `@idUsuarioEjecutor`.
- **Ámbito:** solo COORDINADOR; la asignatura debe estar activa (`ASI_010`), tener vínculo y plan activos en sus programas (`ASI_014`), y el período debe estar vigente, abierto y pertenecer a su institución (`PER_010`).
- **Resultset:** `READ_QUERY_RESULTSET`; filas discriminadas por `tipoFila` (`RESUMEN`, `FRANJA`, `SESION`, `FESTIVO`, `CONFLICTO`). Los conflictos de horario son datos con severidad, no excepciones; insumos inválidos, recursos inexistentes y fallas de ámbito se propagan como `THROW 51000` con código de catálogo.
- **Permisos:** solo `EXECUTE` para `rol_asistencias_runtime`; las consultas internas usan vistas base y no se concede `SELECT` a la vista auxiliar `uv_periodo_academico_cierre`.
- **Pruebas:** `test/test_ses_gen_01_calendario_semestre.sql`; work item `docs/work-items/SES-GEN-01-calendario-semestre/`.

---

## Addendum CULM-001 A — retiro de solicitudes (A.1) y correcciones de la Fase 1 (A.2) (2026-11-07)

Contrato: `AsistenciasUCO-Infra/docs/work-items/CULM-001-culminacion/paquetes/A-retiro-solicitudes/CONTRACT.md` (v5).
Migraciones: `13_culm001_a_retiro_solicitudes_up/down.sql` y `14_culm001_a_correcciones_fase1_up/down.sql`.

| SP | Caso de uso | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_registrar_estudiante_en_grupo` (cambia) | Matrícula manual; firma y resultset sin cambio | solo DOCENTE titular (F-COO-004) | `SEC_001`, `SEC_002`, `GEN_004`, `ERR_CUPO_SUPERADO`, `ERR_MATRICULA_DUPLICADA` |
| `dbo.usp_reactivar_matricula_retirada_interno` (interno) | Reactiva la matrícula `MATRICULA/ESTADO_RETIRADA` (misma fila) con cupo bajo bloqueo | interno | `GEN_001`, `ERR_CUPO_SUPERADO`, `SYS_001` |
| `dbo.usp_consultar_oferta_grupos_estudiante` (cambia) | Oferta HU008 con 19 columnas (sin solicitud) | estudiante | `VAL_001` (THROW) |
| `dbo.usp_consultar_directorio_estudiantes_paginado` | Directorio (listado 12 columnas; detalle 11 + 12 de contexto) | ADMINISTRADOR institución, COORDINADOR programas, DOCENTE grupos propios | `VAL_001` (THROW) |
| `dbo.usp_consultar_estudiantes_grupo_ambito_paginado` | Estudiantes del grupo en todos los estados; `@tamanoPagina NULL` = todas; `@busqueda` opcional (CIERRE-W1A: subcadena en nombre completo o documento, antes de paginar) | titular, administrador de la institución, coordinador (solo sus programas) | `VAL_001`, `SEC_002` (THROW) |
| `dbo.usp_consultar_asistencias_grupo_ambito_paginado` | Asistencias registradas del grupo, filtro de sesión | igual | `VAL_001`, `SEC_002` (THROW) |
| `dbo.usp_consultar_materias_estudiante` / `dbo.usp_consultar_horario_estudiante` | Solo matrícula `MATRICULA/ESTADO_INSCRITA` | estudiante del ejecutor | `VAL_001` (THROW) |
| `dbo.usp_validar_solape_sesion_interno` (interno, DENY) | Rechazo de sesiones cruzadas del grupo o del docente | interno | `SES_017` |
| `dbo.usp_retirar_solicitud_revision_asistencia` | Comando: el estudiante retira su reclamo `P` → `X` | estudiante propietario | `GEN_002`, `SEC_001`, `REV_006`, `REV_007`, `REV_008` |
| `dbo.usp_cambiar_estado_decano` | Comando + `idUsuario`, `personaSinRolesActivos`, `estaActivoDecano` (toggle con `@estaActivo NULL`) | ADMINISTRADOR de la institución | `GEN_002`, `SEC_001`, `DEC_001`, `DEC_002`, `DEC_003` |
| `dbo.usp_buscar_estudiante_por_documento_grupo` | Documento exacto, 0..1 fila, correo enmascarado (DEC-027) | DOCENTE titular del grupo | `VAL_001`, `SEC_002` (THROW) |

Tabla: `Decano.estado BIT NOT NULL DEFAULT 1` (rama Decano de `uv_usuario_perfil` y `uv_decano` filtradas).
Permisos: `schema/security/rol_asistencias_runtime_culm001_a.sql`. Seeds: `33_culm001_a_catalogos.sql`,
`33_culm001_a_mensajes.sql`. Pruebas: `test_culm001_a_retiro_solicitudes.sql`, `test_culm001_a_correcciones.sql`,
`test_culm001_a_fixture_segundo_ambito.sql` y la compuerta manual `scripts/tests/test_migracion_13_culm001_a.ps1`.
Fixture fuera del despliegue: `test/fixtures/culm1_segundo_ambito.sql` (+ `_down`).

## Addendum HU018 / HU019 — plan de estudios y horas programadas del estudiante (2026-11-10)

Decisión de John del 2026-11-10. El estudiante solo ve lo propio: los dos SP resuelven al estudiante desde `@idUsuarioEjecutor` y no reciben identificadores de otro estudiante.

| Objeto | Qué entrega | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_plan_estudio_estudiante` | Lectura nueva (18 columnas): semestres y asignaturas de los planes ACTIVOS de los programas del estudiante. Una fila por semestre y asignatura (vínculo activo, asignatura activa); un semestre sin asignaturas sale en una fila sin asignatura. `cursando`, `idGrupoCursando` y `nombreGrupoCursando` salen de la matrícula `MATRICULA/ESTADO_INSCRITA`. Orden: programa, INP, semestre, orden del carácter y nombre | estudiante ejecutor (`Estudiante.usuario`, `EstudiantePrograma`) | `VAL_001` (THROW) |
| `dbo.usp_consultar_horas_programadas_estudiante` | Lectura nueva (4 columnas): `idEstudianteGrupo`, `idGrupo`, `sesionesProgramadas` y `horasProgramadas` de cada matrícula inscrita. Cuenta las sesiones no canceladas del grupo, dictadas o por dictar (`uv_cumplimiento_sesion_grupo`); un grupo sin sesiones devuelve 0 y 0 | estudiante ejecutor | `VAL_001` (THROW) |

Sin objetos modificados. Permiso aditivo: `schema/security/rol_asistencias_runtime_hu018_hu019.sql`. Migración: `33_hu018_hu019_plan_horas_estudiante_up|down.sql`. Pruebas: `test/test_hu018_hu019_plan_horas_estudiante.sql` y `test/test_hu018_hu019.ps1`. Work item: `docs/work-items/HU018-HU019-plan-horas-estudiante/PLAN.md`.

## Addendum PC — tomas de asistencia como puntos de control (2026-11-11)

Las horas de la sesión se calculan por tramos entre las tomas (puntos de control) y el estudiante reclama una toma concreta. Contrato: `docs/work-items/PC-puntos-control-tomas/CONTRACT.md`. Todas las columnas nuevas van al final.

| Objeto | Qué entrega o cambia | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_resumen_tomas_sesion(@idUsuarioEjecutor, @idCorrelacion, @idSesion)` | Lectura NUEVA (9 columnas): `idEstudiante`, `nombreCompletoEstudiante`, `minutosSesion`, `minutosAsistidos`, `minutosFalta`, `minutosExcusa`, `minutosSinRegistro`, `codigoEstadoSesionEstudiante`, `tomasAusentes`; una fila por matrícula activa (`MATRICULA/ESTADO_INSCRITA`), ordenada por nombre. Sin cabecera: todo sin registro y `NO_DISPONIBLE` | docente titular de la sesión | `GEN_002`, `SEC_001`, `SEC_002` (THROW 51000) |
| `dbo.usp_consultar_tomas_sesion` | Agrega `fechaPuntoControlUtc`, `ordenPuntoControl`, `minutosTramoAnterior`, `minutosTramoSiguiente`, `esEditable`, `editableHastaUtc` (NULL en la fila de una sesión sin tomas). `maximoTomas` vale 20. `horasToma` queda obsoleto | sin cambio | sin cambio |
| `dbo.usp_registrar_asistencias_toma` | Una toma cerrada con toma posterior ya no se corrige | sin cambio | `TOM_012` nuevo |
| `dbo.usp_cerrar_toma_asistencia` / `dbo.usp_cerrar_tomas_vencidas` | Sin cambio de código: el modo MANUAL ahora marca SJC al cerrar (`@marcarAusentes` NULL o cierre automático) | sin cambio | sin cambio |
| `dbo.usp_radicar_solicitud_revision_asistencia_v4(@idEstudiante, @idSesion, @idToma, @categoria, @justificacion, @idsArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor)` | Comando NUEVO: reclamo de una toma; 7 columnas (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`, `idSolicitudRevision`, `totalSoportes`, `idToma`) | estudiante dueño de la matrícula | `GEN_002` (sin toma), `TOM_001`, `REV_026`, `REV_027` y los de v3 |
| `dbo.usp_resolver_solicitud_revision_asistencia` | Parámetro opcional al final `@codigoResultadoAprobacion` (`AN` = sí estuvo presente, `EX` = ausencia justificada; NULL = EX). Con toma solo cambia esa toma; sin toma, AN no se admite | docente titular | `REV_028`, `REV_029` nuevos |
| `dbo.usp_consultar_solicitudes_revision_estudiante` | Agrega `idToma`, `numeroToma`, `fechaPuntoControlUtc`, `codigoResultadoAprobacion` | sin cambio | sin cambio |
| `dbo.usp_consultar_detalle_solicitud_revision_docente` | Agrega `idToma`, `numeroToma`, `fechaPuntoControlUtc`, `codigoResultadoAprobacion`, `codigoRazonCausaToma`, `minutosSesion`, `minutosAsistidos` | sin cambio | sin cambio |
| `dbo.uv_asistencia_toma_estudiante` | Vista NUEVA (lectura del backend): una fila por cabecera y toma con la marca, el estado (`PRESENTE`, `AUSENTE`, `JUSTIFICADA`, `SIN_REGISTRO`), los minutos de los tramos vecinos, la solicitud no retirada y `esReclamable` | filtra el backend por estudiante | — |

`usp_radicar_solicitud_revision_asistencia_v3` no cambia. Permisos: `schema/security/rol_asistencias_runtime_puntos_control.sql`. Migración: `37_pc_tomas_puntos_control_up|down.sql`. Pruebas: `test/test_pc_puntos_control.sql`, `test/test_pc_calculo_tramos.sql` y `test/test_pc_migracion_37.ps1`.

**Mejora 2026-11-12, migración 38 (`38_pc_toma_en_bandeja_reclamos_up|down.sql`):** `dbo.usp_consultar_solicitudes_revision_docente` (R2, bandeja del docente; `GET /api/v1/docente/reclamos`) agrega AL FINAL `idToma`, `numeroToma` y `fechaPuntoControlUtc` de la toma reclamada (NULL en un reclamo de la sesión completa), resueltos como en `usp_consultar_detalle_solicitud_revision_docente` (LEFT JOIN a `uv_toma_punto_control`). Pasa de 28 a 31 columnas (`totalRegistros` sigue en la 25 y `totalSoportes` en la 28). Sin cambios de parámetros, permisos ni tablas. Prueba: `test/test_pc_toma_en_bandeja_reclamos.sql` (PC_BAN_01..04).

**CIERRE-W1A (2026-11-16):** `dbo.usp_consultar_solicitudes_revision_docente` agrega AL FINAL los parámetros opcionales `@busqueda NVARCHAR(100) = NULL` (subcadena en nombre del estudiante, nombre y código de la asignatura y justificación) y `@idGrupo UNIQUEIDENTIFIER = NULL` (solo ese grupo; la titularidad `Docente.usuario = ejecutor` se mantiene, un grupo ajeno da 0 filas). El resultset (31 columnas) no cambia y `totalRegistros` cuenta con los filtros. Sin los parámetros el comportamiento es el anterior. `dbo.usp_consultar_estudiantes_grupo_ambito_paginado` agrega `@busqueda NVARCHAR(100) = NULL` (resultset de 8 columnas sin cambios). Sin migración: solo `CREATE OR ALTER`. Pruebas: `test/test_cierre_w1a_docente_reclamos_padron.sql`. Contrato: backend `docs/work-items/CIERRE-W1A-docente-reclamos-padron/CONTRACT.md`.

## Addendum ATA P1 — edición durante la sesión, denominador del período y aviso de falta por sesión (2026-11-18)

Contrato: `AsistenciasUCO-Infra/docs/contracts/ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS.md` (secciones A, B y C). Todas las columnas nuevas van al final. Migraciones `50_ata_edicion_tomas_denominador_up|down.sql` y `51_ata_aviso_falta_sesion_up|down.sql`. Pruebas: `test/test_ata_p1_tomas_denominador.sql`, `test/test_ata_p1_aviso_falta.sql` y `test/test_ata_p1_migraciones.ps1`.

| Objeto | Qué entrega o cambia | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_registrar_asistencias_toma` | Ya no emite `TOM_012`: mientras la ventana de la sesión esté abierta se corrige cualquier toma (abierta o cerrada). La única barrera temporal es la ventana (`SES_007..010`). El mensaje `TOM_012` se conserva en el catálogo | docente titular | `TOM_012` retirado |
| `dbo.usp_consultar_tomas_sesion` | `esEditable` = ventana abierta; `editableHastaUtc` = `ventanaCierreUtc` para toda toma (NULL en la fila sin tomas). Mismas columnas y orden | sin cambio | sin cambio |
| Parámetro `ASISTENCIA/MARGEN_RETARDO_MINUTOS` | Valor por defecto 0: la ventana cierra al fin de la sesión y `usp_cerrar_tomas_vencidas` (sin cambio) cierra las tomas a esa hora marcando SJC. Sigue siendo editable (0 a 120) | sin cambio | sin cambio |
| `dbo.uv_cumplimiento_sesion_grupo` | Agrega `cuentaParaPeriodo` (0 si la sesión es una solicitud de sesión pendiente o rechazada) | sin cambio | sin cambio |
| `dbo.uv_resumen_asistencia_estudiante_grupo` / `dbo.uv_resumen_asistencia_estudiante_programa_grupo` | Agregan `sesionesPeriodo` y `horasPeriodo` (la de programa solo `horasPeriodo`). `porcentajeInasistencia` y `codigoPermanencia` pasan a medirse sobre `horasPeriodo` (horas de todas las sesiones del período, no solo las dictadas); `horasDictadas`, `sesionesEjecutadas` y `porcentajeInasistenciaSesiones` conservan su significado | sin cambio | sin cambio |
| `dbo.usp_consultar_comparativa_facultades`, `dbo.usp_consultar_comparativa_programas_facultad`, `dbo.usp_consultar_kpis_decano`, `dbo.usp_consultar_kpis_institucion`, `dbo.usp_consultar_consolidado_asistencia_grupos_paginado` | El porcentaje de ausentismo / inasistencia usa `horasPeriodo` como denominador. Columnas y firmas sin cambio (`horasDictadas` se sigue mostrando) | sin cambio | sin cambio |
| `dbo.usp_consultar_sesiones_pendientes_aviso_falta(@idCorrelacion, @tamanoLote)` | Comando de sistema NUEVO (sin usuario; lectura): `idSesion`, `idGrupo`, `fechaHoraFinUtc` de las sesiones terminadas con todas sus tomas cerradas, no canceladas, dentro de `AVISO_FALTA_SESION/HORAS_MAXIMAS_ATRASO` y sin aviso previo; lote = `@tamanoLote` o `AVISO_FALTA_SESION/LOTE`; `HABILITADO = false` da 0 filas | rol runtime (job) | sin cambio |
| `dbo.usp_consultar_faltas_sesion_aviso(@idSesion, @idCorrelacion)` | Comando de sistema NUEVO (lectura): una fila por (estudiante con SJC, toma en SJC) con datos de la sesión, el estudiante (matrícula activa, usuario activo y correo), `numeroToma`, `fechaPuntoControlUtc`, `totalTomasSesion`, `totalTomasEnFalta`, `minutosFalta` y `fechaLimiteReclamoUtc` | rol runtime (job) | sin cambio |
| `dbo.usp_registrar_aviso_falta_sesion(@idSesion, @totalEstudiantesAvisados, @idCorrelacion)` | Comando de sistema NUEVO con la tupla canónica: marca la sesión en `AvisoFaltaSesion`; idempotente (si ya existe, éxito sin escritura) | rol runtime (job) | `GEN_002`, `SES_001` |
| `dbo.AvisoFaltaSesion` | Tabla NUEVA: `sesion` (PK, FK a `Sesion`), `fechaAvisoUtc`, `totalEstudiantesAvisados`, `idCorrelacion` | solo por SP | n/a |


## Addendum ATA D10 — faltas por reclamar del estudiante (2026-11-18)

Contrato: `AsistenciasUCO-Infra/docs/contracts/ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS.md` (sección J.1). Migración `54_ata_faltas_reclamables_estudiante_up|down.sql`.

| Objeto | Qué entrega o cambia | Ámbito | Códigos |
|---|---|---|---|
| `dbo.uv_falta_reclamable_estudiante` | Vista NUEVA: una fila por (matrícula `MATRICULA/ESTADO_INSCRITA`, toma reclamable `esReclamable = 1` de `uv_asistencia_toma_estudiante`) de sesiones con fila en `AvisoFaltaSesion`. Columnas: `idUsuarioEstudiante`, `idEstudianteGrupo`, `idGrupo`, `nombreGrupo`, `idAsignatura`, `nombreAsignatura`, `idSesion`, `numeroSesion`, `fechaHoraInicioUtc`, `fechaHoraFinUtc`, `idToma`, `numeroToma`, `fechaPuntoControlUtc`, `fechaLimiteReclamoUtc` | solo lectura (sin GRANT directo) | n/a |
| `dbo.usp_consultar_faltas_reclamables_estudiante(@idUsuarioEjecutor, @idCorrelacion, @numeroPagina = 1, @tamanoPagina = 20)` | READ_QUERY_RESULTSET NUEVO paginado (THROW 51000). Solo filas del propio estudiante; columnas de la vista sin `idUsuarioEstudiante` más `totalRegistros`. Orden `fechaHoraFinUtc DESC, numeroToma ASC` | perfil ESTUDIANTE | `GEN_002`, `SEC_001`, `PAG_001` |

## Addendum ATA D11 — retiro de la oferta de grupos del estudiante (HU008 descartada, 2026-11-18)

Decisión del usuario: el sistema solo gestiona asistencia; la inscripción a grupos la gestiona otro sistema. Migración `55_ata_retiro_oferta_grupos_estudiante` (up/down). Se retiran `dbo.usp_consultar_oferta_grupos_estudiante` (y su EXECUTE, `rol_asistencias_runtime_hu008.sql`) y el parámetro `OFERTA.INCLUIR_TRANSVERSALES` (seed `24_parametro_oferta_grupos.sql`); las secciones "Addendum HU008" y la fila de `VAL_001` anteriores son históricas. Se conservan `usp_consultar_oferta_creacion_grupo_docente` y la regla de inscripción en el programa (`test/test_hu008_regla_inscripcion_programa.sql`). Prueba: `test/test_ata_k_retiro_oferta_estudiante.sql` y `test/test_ata_k_migracion.ps1`.

## Addendum NOTOMA-001 — aviso a la coordinación cuando el docente no toma asistencia (2026-11-19)

Work item: `AsistenciasUCO-Infra/docs/work-items/NOTOMA-001-aviso-coordinador-sesion-sin-toma/` (addendum propuesto, no congelado). Migración `57_notoma_aviso_sesion_sin_toma_up|down.sql`. Pruebas: `test/test_notoma_aviso_sin_toma.sql` y `test/test_notoma_migraciones.ps1`.

| Objeto | Qué entrega o cambia | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma(@idCorrelacion, @tamanoLote)` | Comando de sistema NUEVO (sin usuario; lectura): `idSesion`, `idGrupo`, `fechaHoraFinUtc` de las sesiones terminadas SIN ninguna toma, no canceladas, sin solicitud pendiente, con la ventana de registro vencida, dentro de `AVISO_SESION_SIN_TOMA/HORAS_MAXIMAS_ATRASO` y sin aviso previo; lote = `@tamanoLote` o `AVISO_SESION_SIN_TOMA/LOTE`; `HABILITADO = false` da 0 filas | rol runtime (job) | sin cambio |
| `dbo.usp_consultar_destinatarios_aviso_sin_toma(@idSesion, @idCorrelacion)` | Comando de sistema NUEVO (lectura): una fila por coordinador activo con correo de los programas vigentes del grupo (una persona sale una vez) con los datos de la sesión y del docente titular; 0 filas si la sesión no existe, está cancelada o tiene tomas | rol runtime (job) | sin cambio |
| `dbo.usp_registrar_aviso_sesion_sin_toma(@idSesion, @totalCoordinadoresAvisados, @idCorrelacion)` | Comando de sistema NUEVO con la tupla canónica: marca la sesión en `AvisoSesionSinToma`; idempotente (si ya existe, éxito sin escritura) | rol runtime (job) | `GEN_002`, `SES_001` |
| `dbo.AvisoSesionSinToma` | Tabla NUEVA: `sesion` (PK, FK a `Sesion`), `fechaAvisoUtc`, `totalCoordinadoresAvisados`, `idCorrelacion` | solo por SP | n/a |
| Parámetros `AVISO_SESION_SIN_TOMA/HABILITADO`, `LOTE`, `HORAS_MAXIMAS_ATRASO` | `true`, 50 y 24; no editables por el administrador | n/a | n/a |
| Plantilla `SESION_SIN_TOMA_COORDINADOR` (es, v1) | Texto del correo y 8 marcadores obligatorios (`coordinador`, `asignatura`, `grupo`, `fecha`, `horaInicio`, `horaFin`, `docente`, `enlaceSesiones`) | n/a | n/a |

## Addendum HU074 — activar o inactivar asignaturas (2026-11-19)

Migración `58_hu074_estado_asignatura_reglas_up|down.sql`. Work item: `docs/work-items/HU074-estado-asignatura/`. Resultsets sin cambio; única extensión de firma, aditiva: `usp_toggle_estado_asignatura` recibe `@estaActivaDeseada BIT = NULL` al final. Pruebas: `test/test_hu074_estado_asignatura.sql` y `test/test_hu074_migracion.ps1`.

| Objeto | Qué entrega o cambia | Ámbito | Códigos |
|---|---|---|---|
| `dbo.usp_toggle_estado_asignatura` | Inactivar (1 → 0) se rechaza si la asignatura tiene grupos en un período vigente o futuro, en cualquier programa (`uv_periodo_academico.estado` distinto de `CERRADO`; misma regla de fechas que `ASI_005`). Reactivar (0 → 1) siempre se permite. Éxito: `ASI_011` (quedó activa) o `ASI_012` (quedó inactiva), en lugar de `GEN_004`. Parámetro aditivo `@estaActivaDeseada BIT = NULL`: `NULL` alterna; `1`/`0` fija ese estado y, si ya está en él, responde éxito sin cambios (`ASI_011`/`ASI_012`) sin evaluar la regla de grupos. La regla de grupos y el `UPDATE` corren en una transacción con la fila de `Asignatura` bloqueada (`UPDLOCK, HOLDLOCK`) | COORDINADOR de todos los programas con vínculo activo | `GEN_002`, `SEC_001`, `VAL_002`, `SEC_002`, `ASI_006`, `ASI_009`, `ASI_011`, `ASI_012`, `SYS_001` |
| `dbo.usp_crear_grupo` | HU074 conserva `ASI_010` para asignatura inactiva y bloquea la fila hasta el `INSERT`. SES-GEN-01 exige vínculo y plan activos en todos los programas del coordinador (`ASI_014`), período explícito y abierto de su institución (`PER_010`); ya no sustituye un período ausente por el más reciente | sin cambio | + `ASI_010`, `ASI_014`, `PER_010` |
| `dbo.usp_asociar_asignatura_plan` | Una asignatura inactiva no se asocia a un plan: `ASI_010` (antes caía en `GEN_001`). `GEN_001` queda para la asignatura inexistente o de otra institución | sin cambio | + `ASI_010` |
| `dbo.usp_consultar_oferta_creacion_grupo_docente`, `dbo.usp_consultar_asignaturas_asociables_paginado` | Sin cambio: ya excluían las asignaturas inactivas (`estaActivaAsignatura = 1`), así que no ofrecen algo que luego se rechaza | sin cambio | sin cambio |
| `dbo.usp_consultar_asignaturas_plan_paginado` (malla) | Sin cambio: muestra las inactivas con `estaActivaAsignatura = 0` (reflejo de `Asignatura.estado`) para que el coordinador las reactive | sin cambio | sin cambio |

Los grupos existentes no cambian al inactivar. El modelo no tiene baja lógica de `Grupo`: cuentan todos los grupos del período vigente o futuro.

## Addendum SKILLS-BD lote 3 (2026-11-25): parámetros, usuarios e identidad

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote3_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 3 |
| :--- | :--- |
| `usp_consultar_perfil_usuario` | Vínculos leídos por `uv_estudiante_identidad`/`uv_estudiante_programa`, `uv_docente_programa`, `uv_coordinador_identidad`, `uv_decano_identidad`, `uv_facultad`, `uv_programa` y `uv_administrador` (antes, tablas base); `TRY/CATCH` que relanza (lectura) |
| `usp_consultar_reenvio_activacion_cuenta` | Usuario destino por `uv_usuario_autenticacion` y última emisión por la vista nueva `uv_token_verificacion_correo` (solo `id`, `idUsuario` y `fechaEmisionUtc`; nunca el hash); `IF` con `BEGIN/END`; `TRY/CATCH` que relanza (el rechazo sigue siendo `THROW 51000`) |
| `usp_corregir_identidad_usuario` | Ámbito del coordinador, del administrador y del decano por vistas `uv_*` (la fila del usuario se sigue leyendo con `UPDLOCK, HOLDLOCK` en `dbo.Usuario`); `correo` y `numeroIdentificacion` devueltos desde `uv_usuario`; `IF` con `BEGIN/END` |
| `usp_vincular_identidad_externa`, `usp_revocar_identidad_externa` | `DECLARE` del `CATCH` movidos a la cabecera; `IF` con `BEGIN/END`. Las lecturas de `IdentidadExterna` y `Usuario` son con bloqueo y siguen en la tabla |
| `usp_sincronizar_mensaje_usuario` | `IF` con `BEGIN/END`; la fecha nueva se relee con `UPDLOCK, HOLDLOCK` (la fila ya está bloqueada; `uv_mensaje_usuario` filtra los mensajes inactivos y no sirve para esta relectura) |

## Addendum SKILLS-BD lote 4 (2026-11-25): decano, facultad, coordinador y programas

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote4_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 4 |
| :--- | :--- |
| `usp_crear_decano_con_facultad` | Rol de decano por `uv_decano_rol` (antes, la tabla); `IF` con `BEGIN/END` |
| `usp_cambiar_estado_decano` | Ámbito del administrador por `uv_facultad` y `uv_administrador`; `IF` con `BEGIN/END`. Las lecturas con `UPDLOCK, HOLDLOCK` (`Decano`, `Programa`) siguen en la tabla |
| `usp_cambiar_estado_coordinador`, `usp_actualizar_coordinador` | `@idCorrelacionDefecto` en mensajes y llamadas internas (el resultset sigue devolviendo el `idCorrelacion` recibido); `DECLARE` del `CATCH` a la cabecera; `IF` con `BEGIN/END` |
| `usp_actualizar_programa_academico`, `usp_cambiar_estado_programa_academico` | `PASO n` y `SET XACT_ABORT ON` (fachadas que mutan) |
| `usp_consultar_coordinadores_facultad_paginado` | Búsqueda sin `ISNULL` (un `CHARINDEX` sobre `NULL` no coincide, igual que sobre cadena vacía); `PASO n` y comentario del `CATCH` de lectura |
| `usp_consultar_estructura_facultad` | Ámbito del decano por `uv_facultad` y `uv_decano_identidad` (antes, las tablas); comentario del `CATCH` de lectura |
| `usp_consultar_programas_academicos` | `DECLARE` en la cabecera (antes, dentro del `BEGIN`); comentario del `CATCH` de lectura |
| `usp_consultar_programas_creditos_facultad_paginado` | Vínculos asignatura-plan por `uv_asignatura_plan_estudio` (antes, la tabla puente más `uv_asignatura`; mismas filas porque todas las FK del camino son `NOT NULL`); `PASO n` y comentario del `CATCH` de lectura |

Los `ISNULL` que quedan en estas consultas son sobre agregaciones (`MAX`, `COUNT`, `SUM`), permitidos por la skill.

## Addendum SKILLS-BD lote 5 (2026-11-26): docentes y grupos

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote5_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 5 |
| :--- | :--- |
| `usp_vincular_docente_programa`, `usp_cambiar_estado_docente_programa` | Existencia del vínculo por `uv_docente_programa` (antes, la tabla; el núcleo lo revalida con bloqueo); `DECLARE` del `CATCH` a la cabecera; `IF` con `BEGIN/END` |
| `usp_actualizar_docente_programa` | `DECLARE` del `CATCH` a la cabecera; `IF` con `BEGIN/END` |
| `usp_crear_grupo` | `IF` con `BEGIN/END`; orden de programas por `uv_programa` (antes, la tabla) |
| `usp_actualizar_grupo` | `IF` con `BEGIN/END`; estado de matrícula por `uv_estado_estudiante_grupo`. Las lecturas con `UPDLOCK` (`Grupo`, `EstudianteGrupo`) siguen en la tabla |
| `usp_consultar_audiencias_realtime_grupo` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, `TRY/CATCH` de lectura y lecturas por `uv_grupo`, `uv_docente_identidad`, `uv_estudiante_grupo` y `uv_periodo_academico` (mismas filas: FK `NOT NULL` en todo el camino) |
| `usp_consultar_programas_grupo` | `PASO n`, `IF` con `BEGIN/END`, `TRY/CATCH` de lectura y titular por `uv_grupo` y `uv_docente_identidad` |
| `usp_consultar_grupos_facultad_paginado` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, `TRY/CATCH` de lectura y facultad del decano por `uv_facultad`, `uv_decano_identidad` y `uv_programa` |
| `usp_consultar_candidatos_docente_programa` | `DECLARE` en la cabecera, `TRY/CATCH` de lectura y vínculo existente por `uv_docente_programa` |
| `usp_consultar_grupos_paginado` | `DECLARE` en la cabecera, programa responsable por `uv_programa` y comentario del `CATCH` de lectura |
| `usp_consultar_docentes_programa`, `usp_consultar_oferta_creacion_grupo_docente` | `DECLARE` en la cabecera; `CATCH` de lectura (comentario o bloque nuevo que relanza) |
| `usp_consultar_docentes_facultad_paginado` | Solo el comentario del `CATCH` de lectura |

Los `CATCH` de las consultas relanzan el error (READ_QUERY_RESULTSET), igual que en los lotes anteriores.

## Addendum SKILLS-BD lote 6 (2026-11-26): asignaturas y planes de estudio

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote6_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 6 |
| :--- | :--- |
| `usp_agregar_semestre_plan_estudio`, `usp_quitar_semestre_plan_estudio` | Plan, semestres y vínculos por `uv_plan_estudio`, `uv_semestre_plan_estudio`, `uv_semestre` y `uv_asignatura_plan_estudio` (antes, las tablas). El bloqueo `UPDLOCK, HOLDLOCK` del plan sigue en la tabla, y las lecturas siguientes van bajo ese bloqueo |
| `usp_cambiar_estado_plan_estudio` | Programa del plan por `uv_plan_estudio` |
| `usp_registrar_o_actualizar_plan_estudio` | Plan existente y unicidad `(programa, inp)` por `uv_plan_estudio` (bajo el bloqueo del programa, que sigue en la tabla); `IF` con `BEGIN/END`; `DECLARE` del `CATCH` a la cabecera |
| `usp_toggle_estado_asignatura` | Sin `COALESCE` (un `IIF` equivalente); `IF` con `BEGIN/END`; `PASO n`. La lectura con `UPDLOCK, HOLDLOCK` sigue en la tabla |
| `usp_consultar_asignaturas_asociables_paginado`, `usp_consultar_asignaturas_plan_paginado` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, `TRY/CATCH` de lectura y plan por `uv_plan_estudio`/`uv_programa` (antes, las tablas) |
| `usp_consultar_asignaturas_coordinador_paginado`, `usp_consultar_planes_estudio_programa_paginado` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END` y `TRY/CATCH` de lectura |
| `usp_buscar_asignaturas_paginado`, `usp_consultar_componentes_formacion` | Comentario del `CATCH` de lectura (y `PASO n` en el primero) |

Los `ISNULL`/`COALESCE` que quedan en este grupo son sobre agregaciones (`MAX`, `SUM`), permitidos por la skill.

## Addendum SKILLS-BD lote 7 (2026-11-26): estudiantes y matrícula en grupo

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote7_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 7 |
| :--- | :--- |
| `usp_registrar_estudiante_en_grupo` | `DECLARE` de los pasos a la cabecera (asignados con `SET` en su paso); usuario, estudiante y tipo de identificación por `uv_usuario`, `uv_estudiante_identidad` y `uv_tipo_identificacion` (antes, las tablas); `IF` con `BEGIN/END` |
| `usp_retirar_estudiante_grupo` | Estados por `uv_estado_estudiante_grupo`; docente y periodo por `uv_docente_identidad` y `uv_periodo_academico`. El bloqueo `UPDLOCK, HOLDLOCK` sigue sobre las tablas `Grupo` y `EstudianteGrupo` |
| `usp_abrir_ventana_matricula_grupo` | Titular por `uv_grupo`/`uv_docente_identidad` (antes, las tablas); `DECLARE` en la cabecera. El token sigue leyéndose con bloqueo en la tabla |
| `usp_cerrar_ventana_matricula_grupo` | `PASO n`, `DECLARE` en la cabecera, `IF` con `BEGIN/END` y `SET XACT_ABORT ON` (fachada que muta y no lo tenía) |
| `usp_actualizar_semestre_estudiante_programa` | Vínculo y semestres por `uv_estudiante_programa` y `uv_semestre` (antes, las tablas); `PASO n` |
| `usp_buscar_estudiante_por_documento_grupo`, `usp_consultar_destinatarios_retiro_estudiante_grupo`, `usp_consultar_estudiantes_grupo_ambito_paginado`, `usp_consultar_directorio_estudiantes_paginado` | Ámbito, grupo, docente y estudiante por vistas `uv_*` (antes, las tablas); `DECLARE` en la cabecera, `PASO n` y `TRY/CATCH` de lectura |
| `usp_consultar_estudiante_facultad_detalle`, `usp_consultar_estudiantes_facultad_paginado` | Facultad del decano por `uv_facultad`/`uv_decano_identidad` (antes, las tablas); `TRY/CATCH` de lectura |
| `usp_consultar_horas_programadas_estudiante`, `usp_consultar_plan_estudio_estudiante` | Estudiante y vínculos por `uv_estudiante_identidad` y `uv_estudiante_programa`; `TRY/CATCH` de lectura |
| `usp_buscar_estudiantes_institucion_paginado`, `usp_consultar_bitacora_estudiante_programa`, `usp_consultar_faltas_reclamables_estudiante`, `usp_consultar_ficha_estudiante_programa`, `usp_consultar_materias_estudiante`, `usp_consultar_ventanas_matricula_por_rotar` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END` y `TRY/CATCH` de lectura que relanza |

Los `ISNULL` que quedan en `usp_consultar_horas_programadas_estudiante` son sobre agregaciones (`SUM`), permitidos por la skill.

## Addendum SKILLS-BD lote 8 (2026-11-26): notificaciones

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote8_caracterizacion.sql` más las de dominio de cada SP.

| SP | Cambio en el lote 8 |
| :--- | :--- |
| `usp_registrar_notificacion_saliente`, `usp_marcar_notificacion_entregada`, `usp_registrar_fallo_notificacion`, `usp_depurar_notificaciones_salientes` | `DECLARE` en la cabecera (los de un paso se asignan con `SET` en ese paso), `PASO n`, `SET XACT_ABORT ON` (fachadas que mutan y no lo tenían) y estados/notificación por `uv_estado_notificacion`/`uv_notificacion_saliente` (antes, las tablas). Sin `COALESCE`/`ISNULL` sobre variables (`IIF` equivalentes) |
| `usp_reservar_notificaciones_salientes` | `PASO n` y `TRY/CATCH` que relanza el mismo error (`51000`). Sin `XACT_ABORT ON` a propósito (excepción E5 de `excepciones-skills-bd.md`) |
| `usp_confirmar_verificacion_correo` | `DECLARE` del `CATCH` a la cabecera, `PASO n`, `IF` con `BEGIN/END` y usuario activo por `uv_usuario`. El bloqueo del token y el `UPDATE` de `Usuario` siguen en las tablas |
| `usp_consultar_reenvio_verificacion_correo` | Ámbito, estudiante, usuario y tokens por `uv_grupo`, `uv_docente_identidad`, `uv_grupo_programa`, `uv_programa`, `uv_coordinador_identidad`, `uv_estudiante_programa`, `uv_estudiante_identidad`, `uv_estudiante_grupo`, `uv_usuario` y `uv_token_verificacion_correo`; `IF` con `BEGIN/END` y `TRY/CATCH` de lectura que relanza (los rechazos siguen saliendo como `THROW 51000` con `DBCODE`) |
| `usp_registrar_aviso_falta_sesion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END` y sesión por `uv_sesion`. La lectura idempotente con `UPDLOCK, HOLDLOCK` sigue en la tabla |
| `usp_consultar_sesiones_pendientes_aviso_falta`, `usp_consultar_faltas_sesion_aviso` | `PASO n`, `IF` con `BEGIN/END`, sin `ISNULL` (`IIF`/`IF` equivalentes), avisos por `uv_aviso_falta_sesion` y `TRY/CATCH` de lectura que relanza |
| `usp_consultar_contacto_notificacion` | `DECLARE` en la cabecera y `PASO n` |

## Addendum SKILLS-BD lote 9 (2026-11-26): periodos, festivos y recesos

Misma firma, mismo resultset y mismos códigos; prueba `test/test_skills_lote9_caracterizacion.sql` más las de dominio de cada SP
(`test_culm001_b1_festivos`, `test_culm001_c_cierre_masivo`, `test_fix_cierre_001/002`, `test_receso_academico`,
`test_usp_periodo_academico_gestion`, `test_val_pru15_periodo_cerrado`, `test_p3_revision_final_bd`).

| SP | Cambio en el lote 9 |
| :--- | :--- |
| `usp_crear_periodo_academico`, `usp_actualizar_periodo_academico` | `PASO n`, `IF` con `BEGIN/END`, `DECLARE` del `CATCH` a la cabecera y las lecturas posteriores al bloqueo por `uv_periodo_academico_fechas` (antes, la tabla). El bloqueo `UPDLOCK, HOLDLOCK` sigue en la tabla |
| `usp_eliminar_periodo_academico` | `PASO n` y cancelaciones por receso por `uv_sesion_cancelacion`/`uv_receso_academico_registro`. Los bloqueos y los `DELETE` siguen en las tablas |
| `usp_crear_receso_academico` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, `IIF` en lugar de `COALESCE` y detalle por `uv_sesion_cancelacion`/`uv_sesion` |
| `usp_retirar_receso_academico` | `PASO n`, `IF` con `BEGIN/END` y periodo/cancelaciones por `uv_periodo_academico_fechas`/`uv_sesion_cancelacion`. El bloqueo del receso sigue en la tabla |
| `usp_aplicar_festivos_grupo` | `PASO n`, `IF` con `BEGIN/END` y grupo por `uv_grupo_registro` (antes, `dbo.Grupo`) |
| `usp_aplicar_festivos_periodo` | `PASO n`, `IF` con `BEGIN/END` y `IIF` en lugar de `ISNULL` sobre variables |
| `usp_cargar_dias_festivos` | `PASO n` e `IF` con `BEGIN/END` |
| `usp_ejecutar_cierre_masivo_periodo` | `PASO n` numerados, `IF` con `BEGIN/END` (también los `COMMIT` de una línea) y lecturas sin bloqueo por `uv_estado_estudiante_grupo`, `uv_tipo_alerta_inasistencia`, `uv_estado_revision_cancelacion`, `uv_grupo_registro`, `uv_estudiante_grupo_registro` y `uv_revision_cancelacion_registro`. El orden de bloqueos (§2.0) no cambia: `PeriodoAcademico`, `RevisionCancelacion` y `EstudianteGrupo` con `UPDLOCK, HOLDLOCK` y los `UPDATE` siguen en las tablas |
| `usp_consultar_carga_festivos_anio`, `usp_consultar_dias_festivos`, `usp_consultar_sesiones_festivo_con_asistencia_paginado`, `usp_consultar_destinatarios_receso_academico`, `usp_consultar_recesos_periodo` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |

## Addendum SKILLS-BD lote 10 (2026-11-26): indicadores y consultas

Misma firma, mismos valores en el resultset y mismos códigos; prueba `test/test_skills_lote10_caracterizacion.sql` más las de dominio
de cada SP (KPI de coordinador, decano e institución, aforo, alerta temprana, alertas, W2A/W2B/W3I/W3M, CULM-001 B.2 y C, puntos de
control y ATA P1).

| SP | Cambio en el lote 10 |
| :--- | :--- |
| `usp_consultar_kpis_coordinador`, `usp_consultar_kpis_decano`, `usp_consultar_kpis_institucion` | `DECLARE` en la cabecera (los que dependen del ámbito resuelto se asignan con `SET` en su paso) y `TRY/CATCH` de lectura que relanza. Mismas consultas y mismas pistas (`OPTION (RECOMPILE)`, `NO_PERFORMANCE_SPOOL`); los `ISNULL` que quedan son sobre `SUM` (permitidos) |
| `usp_consultar_aforo_grupos_facultad`, `usp_consultar_alerta_temprana_programa`, `usp_consultar_resumen_asistencia_estudiante_programa`, `usp_consultar_resumen_docentes_programa`, `usp_consultar_historial_grupos_docente_programa` | `DECLARE` en la cabecera, `IF` con `BEGIN/END`, sin `ISNULL` sobre columnas o parámetros (condiciones `IS NULL` equivalentes) y `TRY/CATCH` de lectura que relanza. El historial lee el vínculo y el periodo por `uv_docente_programa`/`uv_periodo_academico_fechas` |
| `usp_consultar_alertas_estudiante`, `usp_consultar_resumen_asistencia_estudiante`, `usp_consultar_resumen_materias_estudiante` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, estudiante y matrícula por `uv_estudiante_identidad`/`uv_estudiante_grupo_registro` y `TRY/CATCH` de lectura que relanza |
| `usp_consultar_matriz_asistencia_grupo_docente_paginado`, `usp_consultar_resumen_asistencia_grupo_docente_paginado`, `usp_consultar_resumen_tomas_sesion` | Igual, sin `ISNULL` sobre columnas de `LEFT JOIN` (`IIF` equivalentes) y transiciones/revisión/sesión por `uv_transicion_revision_cancelacion`, `uv_revision_cancelacion_registro` y `uv_sesion` |
| `usp_consultar_grupos_pendientes_evaluacion_alertas` | Igual, con grupos, periodos, cortes y matrículas por `uv_grupo_registro`, `uv_periodo_academico_fechas`, `uv_evaluacion_alerta_grupo`, `uv_estudiante_grupo_registro` y `uv_estado_estudiante_grupo` |
| `usp_consultar_asignaturas_ambito_consolidado`, `usp_consultar_docentes_ambito_consolidado`, `usp_consultar_historial_estudiante`, `usp_consultar_resumen_grupos_docente` | `PASO n` también en el restablecimiento del contexto y en el `CATCH` de lectura (ya relanzaba) |
| `usp_evaluar_alertas_inasistencia_grupo` | `PASO n`, `IF` con `BEGIN/END`, sin `ISNULL` (condición e `IF` equivalentes) y lecturas sin bloqueo por vistas (catálogos de alerta y revisión, grupo, matrícula e identidad de las novedades). Los `UPDLOCK, HOLDLOCK` y las escrituras siguen en las tablas; el JSON de novedades es el mismo |

En `usp_consultar_resumen_asistencia_grupo_docente_paginado` (`tieneAdvertenciaVigente`, `tienePerdidaVigente`, `requiereAccionDocente`) y
`usp_consultar_resumen_tomas_sesion` (minutos, estado y tomas ausentes) las columnas que usaban `ISNULL` sobre un `LEFT JOIN` siguen
sin devolver `NULL`, pero los metadatos del resultset las describen ahora como anulables (así describe SQL Server un `IIF`). Los valores
no cambian; solo cambia esa marca de los metadatos.


## Addendum SKILLS-BD lote 11 (2026-11-26): revisiones de cancelación y reclamos

Misma firma, mismos valores en el resultset y mismos códigos; prueba `test/test_skills_lote11_caracterizacion.sql` más las de dominio
de cada SP (CULM-001 C y D.1/D.2, reclamos del estudiante y del docente, SES-04, DEC-073, puntos de control, PRU-13, PRU-15, REC3 y
LB-004D).

| SP | Cambio en el lote 11 |
| :--- | :--- |
| `usp_consultar_destinatarios_reclamo_asistencia`, `usp_consultar_destinatarios_revision_cancelacion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas y `TRY/CATCH` de lectura que relanza |
| `usp_consultar_detalle_solicitud_revision_docente`, `usp_consultar_solicitudes_revision_estudiante` | Igual; la cadena reclamo, asistencia, matrícula, estudiante, sesión, grupo, asignatura, soporte, categoría y razón por `uv_solicitud_revision_asistencia_registro`, `uv_asistencia_registro`, `uv_estudiante_grupo_registro`, `uv_estudiante_identidad`, `uv_usuario`, `uv_sesion_registro`, `uv_grupo_registro`, `uv_asignatura`, `uv_archivo_soporte_registro`, `uv_categoria_justificacion` y `uv_razon_causa`. `soportesJson` sale de un `OUTER APPLY` con `IIF` (antes, `ISNULL`) |
| `usp_consultar_asistencias_grupo_ambito_paginado` | Igual; las comprobaciones de ámbito por `uv_usuario`, `uv_grupo_registro`, `uv_docente_identidad`, `uv_programa`, `uv_facultad`, `uv_administrador`, `uv_coordinador_identidad` y `uv_decano_identidad` |
| `usp_consultar_revisiones_cancelacion_coordinador_paginado`, `_decano_paginado`, `_docente_paginado` | Igual; estados, transiciones, programas y vínculo estudiante-programa por `uv_estado_revision_cancelacion`, `uv_transicion_revision_cancelacion`, `uv_programa` y `uv_estudiante_programa_semestre`. El `ISNULL` que queda es sobre `STRING_AGG` (agregación, permitido) |
| `usp_actualizar_resolutores_revisiones_cancelacion` | `PASO n`, `IF` con `BEGIN/END`, `IIF` en lugar de `ISNULL` y la cola del lote, los catálogos y los resolutores por vistas. El `UPDLOCK, HOLDLOCK` de la revisión y las escrituras siguen en las tablas; el JSON de novedades es el mismo |
| `usp_decidir_revision_cancelacion`, `usp_resolver_revision_cancelacion` | `PASO n`, `IF` con `BEGIN/END` (también los `COMMIT` de una línea), longitudes del motivo con `IIF` (antes, `ISNULL`; mismos 10, 500 y tope 1000) y lecturas sin bloqueo por vistas (`uv_transicion_revision_cancelacion`, `uv_estado_revision_cancelacion`, `uv_estudiante_grupo_registro`, `uv_estado_estudiante_grupo`, `uv_grupo_registro`, `uv_docente_identidad`, `uv_decano_rol`, `uv_tipo_alerta_inasistencia`, `uv_programa`). Los `UPDLOCK, HOLDLOCK` (`RevisionCancelacion`, `EstudianteGrupo`) y las escrituras siguen en las tablas |
| `usp_radicar_solicitud_revision_asistencia` | `IF` con `BEGIN/END` y sesión, matrícula, asistencia y estado por `uv_sesion_registro`, `uv_estudiante_grupo_registro`, `uv_asistencia_registro` y `uv_estado` |
| `usp_resolver_solicitud_revision_asistencia` | `IF` con `BEGIN/END`, `IIF` en lugar de `ISNULL`, `PASO` en el `CATCH` y catálogos y llaves por vistas. Los `UPDLOCK, HOLDLOCK` (`SolicitudRevisionAsistencia`, `DetalleAsistencia`) y las escrituras siguen en las tablas |
| `usp_retirar_solicitud_revision_asistencia` | `IF` con `BEGIN/END`, `PASO` en el `CATCH` y estado, asistencia, matrícula y estudiante por vistas. El `UPDLOCK, HOLDLOCK` del reclamo y la escritura siguen en la tabla |

En `usp_consultar_detalle_solicitud_revision_docente` y `usp_consultar_solicitudes_revision_estudiante` la columna `soportesJson` sigue
sin devolver `NULL` (`'[]'` sin soportes), pero los metadatos del resultset la describen ahora como anulable (así describe SQL Server un
`IIF`). Los valores no cambian; solo cambia esa marca de los metadatos.

## Addendum SKILLS-BD lote 12 (2026-11-26): tomas y QR

Misma firma, mismo resultset (los metadatos de los 19 SP no cambian) y mismos códigos; los 19 SP ya tenían prueba directa de dominio
y se corrieron antes y después (CULM-001 B.1 y B.2 tomas y QR, ATA P1, puntos de control, IDENT-001/002, NOTOMA-001, D.7, DEC-076/077,
MRM, PRU-15, cierre de contrato y auditoría del 2026-11-22).

| SP | Cambio en el lote 12 |
| :--- | :--- |
| `usp_consultar_asistencias_toma_paginado`, `usp_consultar_faltantes_toma_paginado`, `usp_consultar_tomas_sesion` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, toma, sesión, asistencia, detalle y razón por `uv_toma_asistencia_registro`, `uv_sesion_registro`, `uv_asistencia_registro`, `uv_detalle_asistencia_registro` y `uv_razon_causa`, y `TRY/CATCH` de lectura que relanza |
| `usp_consultar_tomas_qr_por_rotar`, `usp_consultar_destinatarios_aviso_sin_toma`, `usp_consultar_sesiones_pendientes_aviso_sin_toma` | Igual; programa por `uv_programa`, avisos ya enviados por `uv_aviso_sesion_sin_toma` e `IIF`/`IS NULL` en lugar de `ISNULL` |
| `usp_consultar_token_verificacion_correo` | `PASO n`, usuario por `uv_usuario` y `TRY/CATCH` de lectura. El token sigue buscándose por su hash en la tabla (excepción E7) |
| `usp_abrir_qr_toma`, `usp_abrir_toma_asistencia`, `usp_cerrar_qr_toma`, `usp_cerrar_toma_asistencia`, `usp_rotar_token_asistencia_toma`, `usp_registrar_asistencias_toma` | `PASO n`, `IF` con `BEGIN/END` y lecturas sin bloqueo por vistas (toma, sesión, modo, estado, docente y matrícula). Los `UPDLOCK, HOLDLOCK` (sesión, toma, tokens) y las escrituras siguen en las tablas; el `ISNULL` que queda es sobre `MAX` (permitido) |
| `usp_registrar_asistencia_por_token` | Igual; las dos búsquedas `FORCESEEK` de la fila propia siguen en las tablas (excepción documentada en `excepciones-skills-bd.md`, E7) |
| `usp_emitir_token_verificacion_correo` | `DECLARE` del `CATCH` a la cabecera, `PASO` en el `CATCH` y usuario por `uv_usuario`. El `UPDATE` con bloqueo y el `INSERT` siguen en la tabla |
| `usp_registrar_aviso_sesion_sin_toma` | `DECLARE` en la cabecera, `PASO n` y sesión por `uv_sesion_registro`. La lectura con `UPDLOCK, HOLDLOCK` y el `INSERT` siguen en la tabla |
| `usp_aplicar_festivos_automatico`, `usp_cargar_dias_festivos_automatico`, `usp_rotar_token_asistencia_automatico` | `PASO n` (y en el primero `IIF` en lugar de `ISNULL`) |

Marca `SP_SISTEMA` (excepción E1): el lote 12 la agrega, solo como comentario de cabecera, a los SP de sistema no congelados que aún no
la tenían, también a los de lotes anteriores (jobs, notificaciones y correo, integraciones y utilidades). No cambia su código.

## Addendum SKILLS-BD lote 13 (2026-11-26): sesiones y horarios

Misma firma, mismo resultset (los metadatos de los 28 SP del lote no cambian) y mismos códigos; las pruebas de dominio de sesiones y
la de caracterización del lote dan el mismo resultado antes y después.

| SP | Cambio en el lote 13 |
| :--- | :--- |
| `usp_consultar_destinatarios_sesion_cancelada`, `usp_consultar_destinatarios_sesion_manual`, `usp_consultar_destinatarios_solicitud_sesion`, `usp_consultar_motivos_cancelacion_sesion`, `usp_consultar_solicitudes_sesion_coordinador_paginado` | `DECLARE` en la cabecera, `PASO n`, `IF` con `BEGIN/END`, lecturas por vistas (programa por `uv_programa_registro`, solicitud y sesión por `uv_solicitud_sesion_registro` y `uv_sesion_registro`) y `TRY/CATCH` de lectura que relanza |
| `usp_consultar_horario_estudiante`, `usp_consultar_sesiones_calendario_docente`, `usp_consultar_sesiones_calendario_estudiante` | Igual; estudiante, docente y matrícula por `uv_estudiante_identidad`, `uv_docente_identidad`, `uv_estudiante_grupo_registro` y `uv_estado_estudiante_grupo` |
| `usp_consultar_solicitudes_sesion_docente_paginado` | Igual; programa y docente por `uv_programa_registro` y `uv_docente_identidad`, e `IIF` en lugar de `ISNULL` |
| `usp_consultar_sesiones_facultad_paginado`, `usp_consultar_sesiones_grupo_paginado`, `usp_consultar_asistencias_sesion_paginado` | `DECLARE` en la cabecera, `PASO n` (y en el `CATCH`, que restaura el contexto y relanza), `IF` con `BEGIN/END`; facultad y decano por `uv_facultad_registro` y `uv_decano_identidad`, solicitud por `uv_solicitud_sesion_registro` y `uv_estado_solicitud_sesion` |
| `usp_aprobar_solicitud_sesion`, `usp_rechazar_solicitud_sesion` | `IF` con `BEGIN/END`, `PASO` en el `CATCH` y solicitud, estado y cancelación por vistas. La lectura con `UPDLOCK, HOLDLOCK` de `dbo.Sesion` y las escrituras siguen en las tablas |
| `usp_cancelar_sesion`, `usp_cancelar_sesion_coordinador` | Igual; cancelación, asistencias y tomas por `uv_sesion_cancelacion`, `uv_asistencia_registro` y `uv_toma_asistencia_registro` |
| `usp_generar_sesiones_grupo_v2` | `PASO n` e `IF` con `BEGIN/END` |

## Addendum SKILLS-BD lote 14 (2026-11-26): objetos congelados (decisión D5)

Misma firma, mismo resultset (los metadatos de `sys.dm_exec_describe_first_result_set_for_object` de los 37 SP intervenidos no
cambian) y mismos códigos; las pruebas de dominio de los SP congelados y la de caracterización del lote dan el mismo resultado antes y
después. Los hashes de `docs/contracts/` se actualizan en el mismo commit (el manifiesto DB-GP-001C no se reescribe: las líneas
`SUPERSEDES` siguen apuntando a su hash original).

| SP | Cambio en el lote 14 |
| :--- | :--- |
| `usp_crear_sesion`, `usp_crear_sesion_v2`, `usp_actualizar_sesion`, `usp_actualizar_sesion_v2` | `PASO 1` (delegación al núcleo) dentro de un `TRY` cuyo `CATCH` solo relanza (`PASO 2`; el núcleo ya captura sus errores) y `PASO 3` de retorno |
| `usp_generar_sesiones_grupo`, `usp_registrar_asistencias_sesion` | `DECLARE` del cuerpo a la cabecera, `PASO n`, `IF` con `BEGIN/END` y lecturas sin bloqueo por vistas (grupo, periodo, zona, horario, día, sesión y matrícula). El correlativo con `UPDLOCK, HOLDLOCK` y las escrituras siguen en las tablas; sin `INSERT ... EXEC` ni tablas `#` |
| `usp_clasificar_procedencia_sesion` | `DECLARE` del `CATCH` a la cabecera, `PASO n`, `IF` con `BEGIN/END` y ambiente por `uv_parametro`; el `UPDLOCK` de la sesión y las escrituras siguen en las tablas |
| `usp_consultar_comparativa_facultades`, `usp_consultar_comparativa_programas_facultad`, `usp_consultar_tendencia_ausentismo`, `usp_consultar_configuracion_reclamos`, `usp_consultar_periodos_academicos_paginado`, `usp_consultar_grupo_facultad_detalle`, `usp_consultar_programas_institucion_paginado`, `usp_consultar_sesiones_materia_estudiante` | `DECLARE` en la cabecera (uno por variable), `PASO n`, `IIF` en lugar de `ISNULL` sobre variables, lecturas por vistas y `TRY/CATCH` de lectura que relanza (los `ISNULL` que quedan son sobre agregaciones, permitido) |
| `usp_consultar_archivo_soporte_autorizado`, `usp_consultar_solicitudes_revision_docente` | Igual; todas las uniones por vistas `uv_*` (soporte, reclamo, asistencia, sesión, grupo, matrícula, usuario, asignatura, categoría y estado) |
| `usp_consultar_auditoria_eventos_paginado`, `usp_consultar_parametros_paginado`, `usp_consultar_consolidado_asistencia_grupos_paginado`, `usp_consultar_cambios_parametro_paginado`, `usp_validar_acceso_reporte_grupo` | `PASO n` (también en la restauración del contexto y en el `CATCH`) e `IIF` en lugar de `ISNULL` |
| `usp_actualizar_parametro`, `usp_sincronizar_parametro_catalogo_externo` | `PASO n`, `IF` con `BEGIN/END`, `IS NULL` en lugar de `ISNULL` y lecturas sin bloqueo por `uv_parametro_registro`, `uv_parametro_edicion_registro` y `uv_sincronizacion_parametro_externo_registro`. Los `UPDLOCK, HOLDLOCK` y las escrituras siguen en las tablas |
| `usp_admitir_estudiante`, `usp_crear_coordinador`, `usp_crear_decano` | `DECLARE` del cuerpo y del `CATCH` a la cabecera, `PASO` en el `CATCH`, `IF` con `BEGIN/END`, `IIF` en lugar de `COALESCE` y lecturas sin bloqueo por vistas (`uv_administrador_registro`, `uv_estudiante_identidad`, `uv_estudiante_programa_registro`, `uv_usuario`, `uv_decano_rol`). Las lecturas con `UPDLOCK` de `dbo.Usuario` y las escrituras siguen en las tablas |
| `usp_registrar_archivo_soporte`, `usp_radicar_solicitud_revision_asistencia_v2`, `usp_radicar_solicitud_revision_asistencia_v3` | `DECLARE` del `CATCH` a la cabecera, `PASO n`, `IF` con `BEGIN/END`; estudiante y archivo por `uv_estudiante_identidad` y `uv_archivo_soporte_registro`. El `UPDLOCK` del soporte y el `INSERT` siguen en la tabla |
| `usp_validar_token_matricula_publico` | `DECLARE` del `CATCH` a la cabecera, `PASO n`, `IF` con `BEGIN/END`; ventana, programa, estudiante y vínculo por `uv_token_matricula_grupo_registro`, `uv_programa_registro`, `uv_estudiante_identidad` y `uv_estudiante_programa_registro` |

Marca `SP_SISTEMA` (excepción E1): se agrega a los congelados `usp_sincronizar_parametro_catalogo_externo` y
`usp_validar_token_matricula_publico`. `usp_validar_carga_masiva_usuarios` ya está retirado (su archivo solo lo borra) y no se toca.

Vistas nuevas: `uv_administrador_registro`, `uv_asignatura_registro`, `uv_parametro_registro` (todas las filas de `CatalogoParametro`, sin el filtro de activos de `uv_parametro`), `uv_parametro_edicion_registro`, `uv_sincronizacion_parametro_externo_registro` (sin los valores), `uv_estudiante_programa_registro` y `uv_token_matricula_grupo_registro` (sin `tokenHash`, `tokenHashAnterior`, `pin` ni `pinAnterior`, excepción E7).
