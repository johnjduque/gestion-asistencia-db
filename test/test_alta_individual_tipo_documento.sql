USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- Alta individual de coordinador y decano con tipo de documento (CULM-001 D.5, conservado por DEC-074).
-- Los casos D5-10 y D5-12 vivian en test_culm001_d5_carga_masiva.sql; al retirarse la carga masiva (DEC-074) se
-- conservan aqui porque prueban la alta individual, no la carga:
--   ALTA_TIPO_DOC_PARAMETRO      usp_crear_coordinador guarda el @idTipoIdIdentificacion recibido y ni usp_crear_coordinador ni
--                                usp_crear_decano tienen el literal 'CC' (el defecto sale de IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO).
--   ALTA_LLAMADAS_SIN_TIPO_DOC   las llamadas sin @idTipoIdIdentificacion siguen funcionando y usan el tipo por defecto.
-- Todo corre en transaccion con ROLLBACK.
-- ============================================================================
PRINT 'TEST START: test_alta_individual_tipo_documento';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoTI UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'TI');
IF @tipoTI IS NULL
    SELECT TOP 1 @tipoTI = id FROM dbo.uv_tipo_identificacion WHERE id <> @tipoCC;

DECLARE @idPrograma1 UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER, @idFacultad1 UNIQUEIDENTIFIER, @idTipoPrograma1 UNIQUEIDENTIFIER;
SELECT TOP 1
    @idPrograma1 = p.id,
    @idTipoPrograma1 = p.idTipoPrograma,
    @idInstitucion = p.idInstitucion,
    @idFacultad1 = p.idFacultad
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 AND p.estaActivoPrograma = 1
ORDER BY p.id;

DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
DECLARE @uDecano1 UNIQUEIDENTIFIER = (SELECT TOP 1 d.idUsuario FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano d ON d.id = f.idDecano WHERE f.id = @idFacultad1);

IF @tipoCC IS NULL OR @tipoTI IS NULL OR @idPrograma1 IS NULL OR @uAdmin IS NULL OR @uDecano1 IS NULL
    THROW 52590, 'TEST FAILED: ALTA_TIPO_DOC faltan fixtures basicos del seed.', 1;

DROP TABLE IF EXISTS #altaCoord;
DROP TABLE IF EXISTS #altaDec;
CREATE TABLE #altaCoord (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #altaDec (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

DECLARE @corr UNIQUEIDENTIFIER, @ok BIT, @msg NVARCHAR(4000);

BEGIN TRANSACTION;
BEGIN TRY
    -- Fixture: segunda facultad con su decano (el seed trae una sola), para el alta de un decano sin tipo de documento
    DECLARE @idFacultad2 UNIQUEIDENTIFIER = NEWID(), @idDecano2 UNIQUEIDENTIFIER = NEWID(), @uDecano2 UNIQUEIDENTIFIER;
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 815000201,
        @primerApellido = N'DecanoDos', @segundoApellido = NULL, @primerNombre = N'QA', @segundoNombre = NULL,
        @correo = N'decano2.alta@uco.edu.co', @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @msg OUTPUT, @mensajeTecnicoResultado = @msg OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 52591, 'TEST FAILED: ALTA_TIPO_DOC fixture del segundo decano.', 1;
    SELECT @uDecano2 = id FROM dbo.Usuario WHERE numeroIdentificacion = 815000201;
    INSERT dbo.Decano (id, usuario) VALUES (@idDecano2, @uDecano2);
    INSERT dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (@idFacultad2, N'QA Facultad Alta Individual', @idInstitucion, @idDecano2, 1);

    -- ALTA_TIPO_DOC_PARAMETRO: el coordinador queda con el tipo de documento recibido; sin literal 'CC' en los SP
    SET @corr = NEWID();
    INSERT #altaCoord
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = 815000101,
        @primerNombre = N'CoordTI',
        @segundoNombre = NULL,
        @primerApellido = N'DocTI',
        @segundoApellido = NULL,
        @correo = N'coord.ti@uco.edu.co',
        @idPrograma = @idPrograma1,
        @idFacultad = @idFacultad1,
        @password = N'HashTest123',
        @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uDecano1,
        @idTipoIdIdentificacion = @tipoTI;

    DECLARE @tipoGuardadoCoord UNIQUEIDENTIFIER = (SELECT tipoIdIdentificacion FROM dbo.Usuario WHERE numeroIdentificacion = 815000101);
    DECLARE @defCoord NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.usp_crear_coordinador'));
    DECLARE @defDec NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.usp_crear_decano'));
    IF NOT EXISTS (SELECT 1 FROM #altaCoord WHERE estadoResultado = 1)
       OR @tipoGuardadoCoord IS NULL OR @tipoGuardadoCoord <> @tipoTI
       OR @defCoord LIKE N'%''CC''%' OR @defDec LIKE N'%''CC''%'
        THROW 52592, 'TEST FAILED: ALTA_TIPO_DOC_PARAMETRO', 1;
    PRINT 'TEST_PASS:ALTA_TIPO_DOC_PARAMETRO';

    -- ALTA_LLAMADAS_SIN_TIPO_DOC: sin @idTipoIdIdentificacion se usa IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO (CC en el seed)
    TRUNCATE TABLE #altaCoord;
    SET @corr = NEWID();
    INSERT #altaCoord
    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = 815000121,
        @primerNombre = N'CoordLegacy',
        @segundoNombre = NULL,
        @primerApellido = N'DocLegacy',
        @segundoApellido = NULL,
        @correo = N'coord.legacy@uco.edu.co',
        @idPrograma = @idPrograma1,
        @idFacultad = @idFacultad1,
        @password = N'HashTest123',
        @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uDecano1;

    SET @corr = NEWID();
    INSERT #altaDec
    EXEC dbo.usp_crear_decano
        @idDecano = NULL,
        @numeroIdentificacion = 815000122,
        @primerNombre = N'DecanoLegacy',
        @segundoNombre = NULL,
        @primerApellido = N'DocLegacy',
        @segundoApellido = NULL,
        @correo = N'decano.legacy@uco.edu.co',
        @idFacultad = @idFacultad2,
        @nombreFacultad = NULL,
        @password = N'HashTest123',
        @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uAdmin;

    DECLARE @tipoDefectoCoord UNIQUEIDENTIFIER = (SELECT tipoIdIdentificacion FROM dbo.Usuario WHERE numeroIdentificacion = 815000121);
    DECLARE @tipoDefectoDec UNIQUEIDENTIFIER = (SELECT tipoIdIdentificacion FROM dbo.Usuario WHERE numeroIdentificacion = 815000122);
    IF NOT EXISTS (SELECT 1 FROM #altaCoord WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM #altaDec WHERE estadoResultado = 1)
       OR @tipoDefectoCoord IS NULL OR @tipoDefectoCoord <> @tipoCC
       OR @tipoDefectoDec IS NULL OR @tipoDefectoDec <> @tipoCC
        THROW 52593, 'TEST FAILED: ALTA_LLAMADAS_SIN_TIPO_DOC', 1;
    PRINT 'TEST_PASS:ALTA_LLAMADAS_SIN_TIPO_DOC';

    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion IN (815000101, 815000121, 815000122, 815000201))
        THROW 52594, 'TEST FAILED: quedaron datos de prueba.', 1;
    IF @@TRANCOUNT <> 0 THROW 52595, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST_PASS:ALTA_TIPO_DOC_TRANCOUNT_ZERO';
    PRINT 'TEST END: test_alta_individual_tipo_documento';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #altaCoord;
    DROP TABLE IF EXISTS #altaDec;
    THROW 52599, @err, 1;
END CATCH;
DROP TABLE IF EXISTS #altaCoord;
DROP TABLE IF EXISTS #altaDec;
GO
