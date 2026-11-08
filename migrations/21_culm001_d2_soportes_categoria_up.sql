-- ============================================================================
-- MIGRACION UP 21: CULM-001 D.2 - varios soportes por reclamo, categoria persistida y soporte obligatorio (CONTRACT D §3.2)
-- Aplica, en este orden: DDL (CategoriaJustificacion.requiereSoporte, SolicitudRevisionAsistencia.categoriaJustificacion con FK e
-- indice, IX_ArchivoSoporte_Solicitud no unico en lugar de UX_ArchivoSoporte_Solicitud), semilla 52 (parametros, requiereSoporte,
-- REV_021..REV_024), restauracion de categorias y vinculos colapsados desde las tablas zz_archivo_* de un down anterior, vistas,
-- usp_internal_radicar_solicitud_revision, v2, v3, usp_consultar_configuracion_reclamos, R2/detalle/lista/descarga con categoria y
-- soportes, y los permisos del rol runtime. Idempotente (CREATE OR ALTER / MERGE / IF NOT EXISTS). Down: 21_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 21 UP: soportes multiples y categoria del reclamo (D.2)';
GO
-- ---- DDL (schema/tables/CategoriaJustificacion.sql, SolicitudRevisionAsistencia.sql, ArchivoSoporte.sql, zz_foreign_keys.sql)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NULL
    ALTER TABLE dbo.CategoriaJustificacion ADD [requiereSoporte] bit NOT NULL
        CONSTRAINT DF_CategoriaJustificacion_requiereSoporte DEFAULT 0;
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [categoriaJustificacion] uniqueidentifier NULL;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'UX_ArchivoSoporte_Solicitud')
    DROP INDEX [UX_ArchivoSoporte_Solicitud] ON [dbo].[ArchivoSoporte];
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'IX_ArchivoSoporte_Solicitud')
    CREATE NONCLUSTERED INDEX [IX_ArchivoSoporte_Solicitud]
    ON [dbo].[ArchivoSoporte] ([solicitudRevisionAsistencia])
    INCLUDE ([estado], [nombreOriginal], [tipoContenido], [tamanioBytes], [fechaAdjuncionUtc]);
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_CategoriaJustificacion')
BEGIN
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [FK_SolicitudRevisionAsistencia_CategoriaJustificacion]
    FOREIGN KEY ([categoriaJustificacion]) REFERENCES [dbo].[CategoriaJustificacion] ([id]);
END
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_Categoria')
    CREATE NONCLUSTERED INDEX [IX_SolicitudRevisionAsistencia_Categoria] ON [dbo].[SolicitudRevisionAsistencia] ([categoriaJustificacion]);
GO
-- ---- schema/seed/52_culm001_d2_parametros_mensajes.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2, semilla 52 = 50 + 2; DEC-044 (1)): varios soportes por reclamo, categoria persistida y soporte
-- obligatorio. Idempotente (MERGE por clave natural); los parametros no pisan `valor` si el administrador ya lo cambio.
--   ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO  tope de soportes de un reclamo (3)
--   ARCHIVO/ESTADO_BORRADOR               estado DRAFT del soporte recien subido (TD-061: sin literal quemado en los SP)
--   ARCHIVO/TIPOS_PERMITIDOS              tipos de contenido que acepta la subida (coincide con CK_ArchivoSoporte_TipoContenido)
-- La fila de edicion de MAXIMO_SOPORTES_POR_RECLAMO ([1, 10]) en CatalogoParametroEdicion la siembra 53_culm001_d3_parametro_edicion.sql
-- (corre despues de esta semilla, con el parametro ya creado); la prueba D2 la verifica.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO', N'3',                                  'INT',    N'3'),
    ('ARCHIVO',  'ESTADO_BORRADOR',             N'DRAFT',                              'STRING', N'DRAFT'),
    ('ARCHIVO',  'TIPOS_PERMITIDOS',            N'application/pdf,image/png,image/jpeg', 'STRING', N'application/pdf,image/png,image/jpeg')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- HU014/HU015: soporte obligatorio por categoria (MED, ACA y LAB). La columna requiereSoporte la crea CategoriaJustificacion.sql.
IF COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NOT NULL
    EXEC sys.sp_executesql N'
        MERGE INTO [dbo].[CategoriaJustificacion] AS Target
        USING (VALUES (N''MED'', 1), (N''CAL'', 0), (N''ACA'', 1), (N''FMA'', 0), (N''LAB'', 1), (N''OTR'', 0)) AS Source (codigo, requiereSoporte)
        ON (Target.codigo = Source.codigo)
        WHEN MATCHED AND Target.requiereSoporte <> Source.requiereSoporte THEN
            UPDATE SET Target.requiereSoporte = Source.requiereSoporte;';
GO

-- Mensajes REV_021..REV_024 (radicacion con categoria y soportes multiples). Idempotente (MERGE por codigo).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REV_021', 'BUSINESS_ERROR', 'MEDIO', N'La categoría de justificación no es válida.'),
    ('REV_022', 'BUSINESS_ERROR', 'MEDIO', N'La categoría «{}» exige adjuntar al menos un soporte.'),
    ('REV_023', 'BUSINESS_ERROR', 'MEDIO', N'Puedes adjuntar como máximo {} soportes.'),
    ('REV_024', 'BUSINESS_ERROR', 'MEDIO', N'Un mismo soporte no se puede adjuntar dos veces.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('REV_021', 'BUSINESS_ERROR', 'MEDIO', N'HU015: la categoría [{}] no existe en CategoriaJustificacion (ni por código ni por nombre).'),
    ('REV_022', 'BUSINESS_ERROR', 'MEDIO', N'HU014: la categoría [{}] tiene requiereSoporte = 1 y la solicitud llegó sin soportes.'),
    ('REV_023', 'BUSINESS_ERROR', 'MEDIO', N'HU015: [{}] soportes superan ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO = [{}].'),
    ('REV_024', 'BUSINESS_ERROR', 'MEDIO', N'HU015: la lista de soportes repite al menos un idArchivoSoporte.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- restauracion desde los archivos zz_archivo_* de un down anterior (DEC-044 (8)); no borra esas tablas
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2', N'U') IS NOT NULL
    UPDATE s SET s.categoriaJustificacion = z.categoriaJustificacion
    FROM dbo.SolicitudRevisionAsistencia s
    INNER JOIN dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 z ON z.id = s.id
    WHERE s.categoriaJustificacion IS NULL
      AND EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion c WHERE c.id = z.categoriaJustificacion);
GO
IF OBJECT_ID(N'dbo.zz_archivo_SoporteColapsado_culm001_d2', N'U') IS NOT NULL
    UPDATE a SET a.estado = 'ATTACHED', a.solicitudRevisionAsistencia = z.idSolicitud, a.fechaAdjuncionUtc = z.fechaAdjuncionUtc,
                 a.fechaCambioEstadoUtc = SYSUTCDATETIME(), a.idCorrelacionAdjuncion = z.idCorrelacionAdjuncion
    FROM dbo.ArchivoSoporte a
    INNER JOIN dbo.zz_archivo_SoporteColapsado_culm001_d2 z ON z.idArchivo = a.id
    INNER JOIN dbo.SolicitudRevisionAsistencia s ON s.id = z.idSolicitud
    WHERE a.estado = 'ORPHAN' AND a.solicitudRevisionAsistencia IS NULL;
GO
-- ---- schema/views/uv_soporte_reclamo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2, HU015): soportes vinculados (ATTACHED) a un reclamo, en orden de adjuncion. Un reclamo puede tener
-- de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO. El estado "adjunto" sale de ARCHIVO/ESTADO_ADJUNTO (sin literal quemado).
-- orden = posicion del soporte dentro del reclamo (1 = el primero adjuntado; desempate por id).
CREATE OR ALTER VIEW [dbo].[uv_soporte_reclamo]
AS
SELECT  idSolicitud       = a.solicitudRevisionAsistencia,
        idArchivo         = a.id,
        nombreOriginal    = a.nombreOriginal,
        tipoContenido     = a.tipoContenido,
        tamanioBytes      = a.tamanioBytes,
        fechaAdjuncionUtc = a.fechaAdjuncionUtc,
        orden             = ROW_NUMBER() OVER (PARTITION BY a.solicitudRevisionAsistencia ORDER BY a.fechaAdjuncionUtc, a.id)
FROM    dbo.ArchivoSoporte a
WHERE   a.solicitudRevisionAsistencia IS NOT NULL
  AND   a.estado = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10))
GO
-- ---- schema/views/uv_categoria_justificacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU005/HU016: categorias de justificacion (catalogo de solo consulta). El runtime recibe SELECT con el resto de
-- vistas uv_* (rol_asistencias_runtime.sql). CULM-001 D.2: + requiereSoporte (HU014: la categoria exige al menos un soporte).
CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion]
AS
SELECT  id,
        codigo,
        nombre,
        descripcion,
        requiereSoporte
FROM    dbo.CategoriaJustificacion
GO
-- ---- schema/views/uv_solicitud_revision_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_solicitud_revision_asistencia]
AS
SELECT		id = sr.id,
			nombre = sr.nombre,
			idAsistencia = asi.id,
			fecha = sr.fecha,
			idEstado = est.id,
			nombreEstado = est.nombre,
			justificacionSolicitud = sr.justificacionSolicitud,
			justificacionRespuesta = sr.justificacionRespuesta,
			-- CULM-001 D.2 (TD-060, HU015): categoria persistida y total de soportes vinculados (columnas al final)
			idCategoriaJustificacion = cat.id,
			codigoCategoria = cat.codigo,
			nombreCategoria = cat.nombre,
			totalSoportes = (SELECT COUNT(*) FROM uv_soporte_reclamo sop WHERE sop.idSolicitud = sr.id)

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
LEFT JOIN	CategoriaJustificacion cat
ON			sr.categoriaJustificacion = cat.id
GO
-- ---- schema/stored-procedures/usp_internal_radicar_solicitud_revision.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_radicar_solicitud_revision  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2, DEC-044 (3))
--
-- Nucleo interno COMUN de la radicacion de un reclamo: NO se concede a ningun rol. Lo invocan
-- usp_radicar_solicitud_revision_asistencia_v2 (un solo soporte) y _v3 (de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO) con
-- parametros OUTPUT, sin INSERT-EXEC (Msg 3915, DEC-036): no emite resultset; el llamador emite el suyo.
--
-- Orden (cada paso solo se evalua si los anteriores pasaron; un rechazo no escribe nada):
--   correlacion -> ejecutor -> RBAC ESTUDIANTE -> estudiante -> propiedad (H-01) -> sesion -> matricula
--   -> reejecucion idempotente por correlacion (algun soporte ya ATTACHED con la MISMA correlacion y del mismo dueno:
--      devuelve la solicitud y el total originales sin escribir)
--   -> plazo de excusas (usp_internal_validar_plazo_justificacion, D.1: REV_020 / REV_025)
--   -> categoria por codigo o por nombre (REV_021)
--   -> JSON valido (arreglo de GUID) y GUID distintos (GEN_002 / REV_024)
--   -> cantidad <= ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO (REV_023)
--   -> categoria con requiereSoporte y 0 soportes (REV_022)
--   -> cada soporte WITH (UPDLOCK, HOLDLOCK) en orden de id: dueno = ejecutor y estado ARCHIVO/ESTADO_BORRADOR
--      (inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin revelar el motivo)
--   -> INSERT de la solicitud (categoria y fecha LOCAL de radicacion) -> UPDATE de todos los soportes a ARCHIVO/ESTADO_ADJUNTO
--   -> verificacion por lectura de las N filas.
-- Los estados de soporte y de reclamo salen de parametros (TD-061), no de literales.
-- Ownership transaccional: transaccion propia si @@TRANCOUNT = 0, si no SAVE TRANSACTION (solo se revierte lo escrito).
-- En @estadoResultado = 1 con reejecucion idempotente no se escribe nada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_radicar_solicitud_revision]
(
    @idEstudiante             UNIQUEIDENTIFIER,
    @idSesion                 UNIQUEIDENTIFIER,
    @categoria                NVARCHAR(50),
    @justificacion            NVARCHAR(MAX),
    @idsArchivoSoporte        NVARCHAR(MAX),
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @idSolicitudRevision      UNIQUEIDENTIFIER OUTPUT,
    @totalSoportes            INT              OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @estadoAdjunto            VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @estadoBorrador           VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @codigoPendiente          NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(5));

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @idCategoria          UNIQUEIDENTIFIER;
    DECLARE @nombreCategoria      NVARCHAR(50);
    DECLARE @requiereSoporte      BIT = 0;

    -- Lista de soportes: @ids en el orden recibido; @ordenados sin repetidos y por id (orden fijo de bloqueo)
    DECLARE @ids TABLE (orden INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NULL);
    DECLARE @ordenados TABLE (pos INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NOT NULL);
    DECLARE @jsonValido           BIT = 1;
    DECLARE @cantidad             INT = 0;
    DECLARE @distintos            INT = 0;
    DECLARE @maximo               INT;
    DECLARE @pos                  INT = 1;
    DECLARE @idArchivo            UNIQUEIDENTIFIER;
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @solicitudSoporte     UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;
    DECLARE @textoCantidad        NVARCHAR(20);
    DECLARE @textoMaximo          NVARCHAR(20);
    DECLARE @descartado           NVARCHAR(4000);

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SET @idSolicitudRevision     = NULL;
    SET @totalSoportes           = 0;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Lista de soportes (arreglo JSON de GUID). Solo se lee aqui; los errores se informan en su turno.
        IF @idsArchivoSoporte IS NOT NULL AND LEN(TRIM(@idsArchivoSoporte)) > 0
        BEGIN
            IF ISJSON(@idsArchivoSoporte) = 1 AND LEFT(LTRIM(@idsArchivoSoporte), 1) = N'['
            BEGIN
                INSERT @ids (id)
                SELECT TRY_CAST(j.[value] AS UNIQUEIDENTIFIER)
                FROM OPENJSON(@idsArchivoSoporte) j
                ORDER BY CAST(j.[key] AS INT);
                IF EXISTS (SELECT 1 FROM OPENJSON(@idsArchivoSoporte) j WHERE j.[type] <> 1)
                   OR EXISTS (SELECT 1 FROM @ids WHERE id IS NULL)
                    SET @jsonValido = 0;
            END
            ELSE
                SET @jsonValido = 0;
        END
        SELECT @cantidad = COUNT(*), @distintos = COUNT(DISTINCT id) FROM @ids;

        -- PASO 9: Transaccion propia (o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_culm001_d2_radicar;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 10: Reejecucion idempotente por correlacion (antes del plazo: un reintento legitimo tras el vencimiento
        -- devuelve el exito original). Es un soporte ya vinculado con ESTA correlacion y del mismo dueno.
        IF @estadoResultado = 1 AND @jsonValido = 1 AND @cantidad > 0
        BEGIN
            SELECT TOP 1 @solicitudSoporte = a.solicitudRevisionAsistencia
            FROM dbo.ArchivoSoporte a
            INNER JOIN @ids i ON i.id = a.id
            WHERE a.estado = @estadoAdjunto
              AND a.idCorrelacionAdjuncion = @idCorrelacionDefecto
              AND a.usuarioPropietario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;
            IF @solicitudSoporte IS NOT NULL
            BEGIN
                SET @esReintento = 1;
                SET @idSolicitudRevision = @solicitudSoporte;
            END
        END

        -- PASO 11: Plazo de excusas (D.1). Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 12: Categoria por codigo o por nombre (el codigo gana si ambos coinciden con filas distintas)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SELECT TOP 1 @idCategoria = c.id, @nombreCategoria = c.nombre, @requiereSoporte = c.requiereSoporte
            FROM dbo.CategoriaJustificacion c
            WHERE c.codigo = @categoriaDefecto OR c.nombre = @categoriaDefecto
            ORDER BY IIF(c.codigo = @categoriaDefecto, 0, 1), c.id;
            IF @idCategoria IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_021', @p_param1 = @categoriaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 13: JSON valido y soportes distintos
        IF @estadoResultado = 1 AND @esReintento = 0 AND @jsonValido = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idsArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad <> @distintos
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_024',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 14: Cantidad maxima de soportes (ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @maximo = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO');
            IF @maximo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002', @p_param1 = 'ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @cantidad > @maximo
            BEGIN
                SET @textoCantidad = CONVERT(NVARCHAR(20), @cantidad);
                SET @textoMaximo = CONVERT(NVARCHAR(20), @maximo);
                -- El mensaje de usuario usa solo {1} (maximo); el tecnico usa {1}=cantidad, {2}=maximo.
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoMaximo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @descartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoCantidad, @p_param2 = @textoMaximo,
                    @mensajeUsuarioResultado = @descartado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 15: Soporte obligatorio segun la categoria (HU014)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @requiereSoporte = 1 AND @cantidad = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_022', @p_param1 = @nombreCategoria,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 16: Bloqueo de cada soporte en orden de id (UPDLOCK, HOLDLOCK serializa radicaciones concurrentes con el mismo fileId)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad > 0
        BEGIN
            INSERT @ordenados (id) SELECT DISTINCT id FROM @ids ORDER BY id;
            WHILE @pos <= (SELECT COUNT(*) FROM @ordenados) AND @estadoResultado = 1 AND @esReintento = 0
            BEGIN
                SELECT @idArchivo = o.id FROM @ordenados o WHERE o.pos = @pos;
                SET @propietarioSoporte = NULL; SET @estadoSoporte = NULL; SET @correlacionAdjuncion = NULL; SET @solicitudSoporte = NULL;
                SELECT @propietarioSoporte   = a.usuarioPropietario,
                       @estadoSoporte        = a.estado,
                       @correlacionAdjuncion = a.idCorrelacionAdjuncion,
                       @solicitudSoporte     = a.solicitudRevisionAsistencia
                FROM dbo.ArchivoSoporte a WITH (UPDLOCK, HOLDLOCK)
                WHERE a.id = @idArchivo;

                IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
                BEGIN
                    SET @estadoResultado = 0;
                END
                ELSE IF @estadoSoporte = @estadoAdjunto AND @correlacionAdjuncion = @idCorrelacionDefecto
                BEGIN
                    -- Carrera con la misma solicitud (doble envio): la otra sesion ya confirmo; es una reejecucion
                    SET @esReintento = 1;
                    SET @idSolicitudRevision = @solicitudSoporte;
                END
                ELSE IF @estadoSoporte <> @estadoBorrador
                BEGIN
                    SET @estadoResultado = 0;
                END

                IF @estadoResultado = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
                SET @pos += 1;
            END
        END

        -- PASO 17: Creacion de la solicitud y vinculo atomico de los N soportes
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SET @fechaLocalRadicacion = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE);

            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo = @codigoPendiente ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta, categoriaJustificacion
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                '',
                @idCategoria
            );

            IF @cantidad > 0
            BEGIN
                UPDATE a
                SET estado = @estadoAdjunto,
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                FROM dbo.ArchivoSoporte a
                INNER JOIN @ordenados o ON o.id = a.id
                WHERE a.estado = @estadoBorrador
                  AND a.usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): los N soportes quedaron vinculados a ESTA solicitud.
                IF @filasActualizadas <> @cantidad
                   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN @ordenados o ON o.id = a.id
                       WHERE a.estado = @estadoAdjunto AND a.solicitudRevisionAsistencia = @nuevaSolicitudId) <> @cantidad
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            IF @estadoResultado = 1
                SET @idSolicitudRevision = @nuevaSolicitudId;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @totalSoportes = COUNT(*) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @idSolicitudRevision;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
        ELSE
        BEGIN
            SET @idSolicitudRevision = NULL;
            SET @totalSoportes = 0;
        END

        -- PASO 18: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH
END;
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v2.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2)
--
-- Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte
-- (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta.
--
--   * Sin @soporteNombre/@soporteUrl: la v2 no confia en datos de soporte del cliente.
--   * Verifica que @idEstudiante pertenezca a @idUsuarioEjecutor (defensa en profundidad, H-01).
--   * Soporte inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin escritura.
--   * Reintento con la misma correlacion tras un exito => exito idempotente (sin segunda solicitud).
--   * Carrera por el mismo fileId: el UPDLOCK sobre la fila serializa; la segunda ve ATTACHED => ARC_001.
--   * CULM-001 D.1 (HU026B): el plazo de excusas se valida DESPUES de la reejecucion idempotente por correlacion y antes de
--     cualquier escritura (REV_020 vencido, REV_025 sin parametros). `fecha` es la fecha LOCAL de radicacion.
--   * CULM-001 D.2 (HU014/HU015, TD-060; CONTRACT §3.2, DEC-044 (3)): firma y resultset SIN CAMBIO (4 columnas), pero la logica vive
--     ahora en usp_internal_radicar_solicitud_revision (compartida con usp_radicar_solicitud_revision_asistencia_v3): arma
--     ["@idArchivoSoporte"] (o NULL), guarda la categoria (REV_021 si no existe en CategoriaJustificacion) y exige soporte segun
--     la categoria (REV_022: MED, ACA y LAB). Los estados de soporte salen de parametros (TD-061).
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v2]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idArchivoSoporte   UNIQUEIDENTIFIER = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idsArchivoSoporte    NVARCHAR(MAX)    = IIF(@idArchivoSoporte IS NULL, NULL, CONCAT(N'["', CAST(@idArchivoSoporte AS NVARCHAR(36)), N'"]'));
    DECLARE @idSolicitudRevision  UNIQUEIDENTIFIER = NULL;
    DECLARE @totalSoportes        INT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_lb004d_radicar_v2;
            SET @savepointCreado = 1;
        END

        EXEC dbo.usp_internal_radicar_solicitud_revision
            @idEstudiante = @idEstudiante,
            @idSesion = @idSesion,
            @categoria = @categoria,
            @justificacion = @justificacion,
            @idsArchivoSoporte = @idsArchivoSoporte,
            @idCorrelacion = @idCorrelacionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idSolicitudRevision = @idSolicitudRevision OUTPUT,
            @totalSoportes = @totalSoportes OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        -- Con savepoint (transaccion del llamador) no se revierte aqui: usp_internal_radicar_solicitud_revision ya revierte a su propio
        -- savepoint lo que escribio si fallo, y un rechazo previo a las escrituras no deja nada que deshacer (ROLLBACK esta
        -- prohibido dentro de un INSERT-EXEC del llamador, Msg 3915).
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v3.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v3  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2)
--
-- Radica el reclamo con CATEGORIA persistida (FK a CategoriaJustificacion) y de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO soportes
-- (DRAFT -> ATTACHED, todos en la MISMA transaccion). Toda la logica vive en usp_internal_radicar_solicitud_revision (compartida con
-- v2, DEC-044 (3)); aqui solo se gestiona la transaccion y se emite el resultset (los resultados vuelven por parametros OUTPUT, Msg 3915).
--
--   @categoria         codigo (MED, CAL...) o nombre de la categoria (REV_021 si no existe)
--   @idsArchivoSoporte arreglo JSON de GUID (["guid", ...]) o NULL/'[]' sin soportes; categoria con requiereSoporte exige >= 1 (REV_022)
--
-- Resultset: MUTATION_COMMAND_RESULTSET extendido: las 4 columnas canonicas (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idSolicitudRevision y totalSoportes (NULL / 0 si fallo).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v3]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idsArchivoSoporte  NVARCHAR(MAX) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudRevision  UNIQUEIDENTIFIER = NULL;
    DECLARE @totalSoportes        INT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_culm001_d2_radicar_v3;
            SET @savepointCreado = 1;
        END

        EXEC dbo.usp_internal_radicar_solicitud_revision
            @idEstudiante = @idEstudiante,
            @idSesion = @idSesion,
            @categoria = @categoria,
            @justificacion = @justificacion,
            @idsArchivoSoporte = @idsArchivoSoporte,
            @idCorrelacion = @idCorrelacionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idSolicitudRevision = @idSolicitudRevision OUTPUT,
            @totalSoportes = @totalSoportes OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        -- Con savepoint (transaccion del llamador) no se revierte aqui: usp_internal_radicar_solicitud_revision ya revierte a su propio
        -- savepoint lo que escribio si fallo, y un rechazo previo a las escrituras no deja nada que deshacer (ROLLBACK esta
        -- prohibido dentro de un INSERT-EXEC del llamador, Msg 3915).
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_culm001_d2_radicar_v3;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: las 4 columnas canonicas + el resultado de la radicacion
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSolicitudRevision     = @idSolicitudRevision,
        totalSoportes           = @totalSoportes;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_configuracion_reclamos.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_configuracion_reclamos  (CULM-001 D.2, HU015; CONTRACT §3.2 GET /api/v1/configuracion/reclamos)
--
-- Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 ante validacion fallida).
-- Una fila con la configuracion institucional del formulario de reclamos para que el cliente no la duplique:
--   maximoSoportes          ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO
--   tamanioMaximoBytes      ARCHIVO/TAMANIO_MAXIMO_BYTES
--   tiposPermitidos         ARCHIVO/TIPOS_PERMITIDOS (tipos de contenido separados por coma)
--   limiteSubidasPorMinuto  ARCHIVOS/LIMITE_SUBIDAS_POR_MINUTO
--   diasLimiteJustificacion ASISTENCIA/DIAS_LIMITE_JUSTIFICACION
-- RBAC: ESTUDIANTE o DOCENTE (el docente ve los mismos limites que aplican al estudiante). Sin escrituras ni transacciones.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_configuracion_reclamos]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'ESTUDIANTE,DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        maximoSoportes          = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO'),
        tamanioMaximoBytes      = CAST(TRY_CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'TAMANIO_MAXIMO_BYTES') AS NVARCHAR(40)) AS BIGINT),
        tiposPermitidos         = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'TIPOS_PERMITIDOS') AS NVARCHAR(500)),
        limiteSubidasPorMinuto  = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'LIMITE_SUBIDAS_POR_MINUTO'),
        diasLimiteJustificacion = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
END;
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_revision_docente.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_docente  (LB-004D, R2)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Otro docente => 0 filas. Une tablas base; no usa
-- SESSION_CONTEXT ni uv_auth_*.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: nombre del estudiante, sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060/TD-061): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las
-- del PRIMER soporte adjuntado (contrato posicional) y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a
-- la categoria persistida) y totalSoportes. El estado adjunto sale de ARCHIVO/ESTADO_ADJUNTO (sin literal 'quemado').
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @estadoAdjunto VARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        totalRegistros                = COUNT(*) OVER(),
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        totalSoportes                 = (SELECT COUNT(*) FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id)
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    WHERE doc.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_detalle_solicitud_revision_docente.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solicitud de revision).
-- Los parametros invalidos se propagan con THROW (como usp_consultar_solicitudes_revision_docente, R2).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Solicitud inexistente o ajena => 0 filas (no distingue
-- ambos casos para no revelar existencia). Solo lectura: sin transaccion explicita.
--
-- Causal: DetalleAsistencia y RazonCausa se unen con LEFT JOIN (la solicitud existe aunque falte el detalle).
-- Soporte: ArchivoSoporte se une con LEFT JOIN y solo en el estado definido por el parametro
-- ARCHIVO.ESTADO_ADJUNTO (sin literales quemados).
--
-- Semantica temporal: igual que R2. fechaSolicitud es DATE de calendario; fechaHoraInicioSesion es el
-- DATETIME2(7) de dbo.Sesion TAL CUAL con procedenciaTemporalSesion (NULL = INDETERMINADA, historica);
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7). Datos personales minimos: sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_detalle_solicitud_revision_docente]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idSolicitud IS NULL OR @idSolicitudDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'Solicitud',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        asistio                       = CAST(CASE WHEN det.codigoRazonCausaConsolidado IS NULL THEN NULL WHEN det.codigoRazonCausaConsolidado = N'AN' THEN 1 ELSE 0 END AS BIT),
        codigoRazonCausa              = rzc.codigo,
        nombreRazonCausa              = rzc.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]')
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    -- CULM-001 B.2 (CONTRACT §2.9): estado consolidado de la sesion (una fila aunque haya varias tomas)
    OUTER APPLY (SELECT h.codigoRazonCausaConsolidado FROM dbo.uv_asistencia_sesion_horas h WHERE h.idAsistencia = asi.id) det
    LEFT  JOIN dbo.RazonCausa rzc         ON rzc.codigo = det.codigoRazonCausaConsolidado
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    WHERE sra.id = @idSolicitudDefecto
      AND doc.usuario = @idUsuarioDefecto;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_revision_estudiante.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_estudiante  (HU010/HU011, consulta)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance (ownership en persistencia): SOLO solicitudes cuya cadena
-- SolicitudRevisionAsistencia -> Asistencia -> EstudianteGrupo -> Estudiante tiene Estudiante.usuario = ejecutor.
-- Otro estudiante, un docente o un coordinador => 0 filas. Une tablas base; no usa SESSION_CONTEXT ni uv_auth_*.
-- Resultset con las MISMAS columnas y tipos que usp_consultar_solicitudes_revision_docente (R2, LB-004D):
-- idEstudiante/nombreEstudiante son los del propio ejecutor. El soporte vinculado se resuelve con el
-- parametro ARCHIVO.ESTADO_ADJUNTO (sin literales quemados), igual que el detalle HU035/HU036.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: solo el nombre del propio estudiante, sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_estudiante]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @estadoAdjunto VARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        totalRegistros                = COUNT(*) OVER(),
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]')
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_archivo_soporte_autorizado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_archivo_soporte_autorizado  (LB-004D, R1)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: el
-- resultset de 4 columnas aplica solo a comandos, por eso este SP queda excluido de esa regla en
-- test/test_contract_closure.sql. Los parametros invalidos se propagan con THROW (como
-- usp_consultar_grupos_paginado).
--
-- Autorizacion (se resuelve aqui, ANTES de que el backend pida bytes al storage):
--   PROPIETARIO     usuarioPropietario = ejecutor y estado IN (DRAFT, ATTACHED)
--   DOCENTE_TITULAR estado = ATTACHED y el ejecutor es Docente.usuario del Grupo.docente de la
--                   sesion de la asistencia de la solicitud
-- Cualquier otro caso (inexistente, otro estudiante incluso del mismo grupo, docente no titular,
-- administrador, decano, coordinador, ORPHAN) => 0 filas, sin senal que distinga los casos.
-- CULM-001 D.2 (TD-061, CONTRACT §3.2): un reclamo tiene varios soportes y CADA uno se autoriza por separado con estas mismas reglas;
-- los estados DRAFT/ATTACHED salen de ARCHIVO/ESTADO_BORRADOR y ARCHIVO/ESTADO_ADJUNTO (sin literales quemados).
-- Une tablas base: NO usa SESSION_CONTEXT ni uv_auth_* (que exponen reclamos a companeros/roles
-- administrativos, hallazgo H-03).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_archivo_soporte_autorizado]
(
    @idArchivoSoporte   UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idArchivoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArchivoSoporte, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoBorrador       VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Validacion de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idArchivoSoporte IS NULL OR @idArchivoDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = 'idArchivoSoporte',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idArchivoSoporte              = a.id,
        estado                        = a.estado,
        nombreOriginal                = a.nombreOriginal,
        tipoContenido                 = a.tipoContenido,
        tamanioBytes                  = a.tamanioBytes,
        checksumSha256                = a.checksumSha256,
        fechaRegistroUtc              = a.fechaRegistroUtc,
        fechaAdjuncionUtc             = a.fechaAdjuncionUtc,
        idSolicitudRevisionAsistencia = a.solicitudRevisionAsistencia,
        relacionAcceso                = CAST(CASE
                                            WHEN a.usuarioPropietario = @idUsuarioDefecto
                                                 AND a.estado IN (@estadoBorrador, @estadoAdjunto) THEN 'PROPIETARIO'
                                            ELSE 'DOCENTE_TITULAR'
                                        END AS VARCHAR(20))
    FROM dbo.ArchivoSoporte a
    WHERE a.id = @idArchivoDefecto
      AND (
            (a.usuarioPropietario = @idUsuarioDefecto AND a.estado IN (@estadoBorrador, @estadoAdjunto))
         OR (a.estado = @estadoAdjunto
             AND EXISTS (
                SELECT 1
                FROM dbo.SolicitudRevisionAsistencia sra
                INNER JOIN dbo.Asistencia asi ON asi.id = sra.asistencia
                INNER JOIN dbo.Sesion ses     ON ses.id = asi.sesion
                INNER JOIN dbo.Grupo gru      ON gru.id = ses.grupo
                INNER JOIN dbo.Docente doc    ON doc.id = gru.docente
                WHERE sra.id = a.solicitudRevisionAsistencia
                  AND doc.usuario = @idUsuarioDefecto))
          );
END;
GO
-- ---- schema/security/rol_asistencias_runtime_culm001_d2.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2): permisos de varios soportes por reclamo (HU014/HU015). EXECUTE sobre el comando v3 y la consulta de
-- configuracion; SELECT sobre uv_soporte_reclamo. El nucleo usp_internal_radicar_solicitud_revision NO se concede (lo invocan v2 y v3).
-- usp_radicar_solicitud_revision_asistencia_v2 conserva el GRANT de rol_asistencias_runtime_lb004d.sql. Aditivo e idempotente: el bucle
-- uv_* de rol_asistencias_runtime.sql ya cubre la vista cuando deploy_schema.ps1 aplica la seguridad despues de las vistas; el GRANT
-- explicito cubre los objetos creados por la migracion 21 fuera de ese despliegue.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_radicar_solicitud_revision_asistencia_v3] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_configuracion_reclamos] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_soporte_reclamo] TO [rol_asistencias_runtime];
GO
