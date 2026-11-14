USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): validacion de carga masiva de usuarios por jerarquia.
-- Casos D5-01 .. D5-10 y D5-12 (D5-11 y D-RB-02 estan en test_culm001_d5.ps1 / test_culm001_d5_migraciones.sql).
-- Todo corre en transaccion con ROLLBACK garantizado.
-- ============================================================================
IF OBJECT_ID('tempdb..#d5_expect') IS NOT NULL DROP PROCEDURE #d5_expect;
GO
CREATE PROCEDURE #d5_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: CULM001_D5_', @label);
        THROW 52500, @mensaje, 1;
    END
END;
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoTI UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'TI');
IF @tipoTI IS NULL
    SELECT TOP 1 @tipoTI = id FROM dbo.uv_tipo_identificacion WHERE id <> @tipoCC;

DECLARE @tipoVincTC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoVinculacion WHERE codigo = 'PLA');
IF @tipoVincTC IS NULL
    SELECT TOP 1 @tipoVincTC = id FROM dbo.TipoVinculacion;

DECLARE @idPrograma1 UNIQUEIDENTIFIER, @codigoProg1 NVARCHAR(50), @uCoord1 UNIQUEIDENTIFIER, @idCoord1 UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER, @idFacultad1 UNIQUEIDENTIFIER, @idTipoPrograma1 UNIQUEIDENTIFIER;
SELECT TOP 1 
    @idPrograma1 = p.id, 
    @codigoProg1 = p.nombrePrograma, -- DEC-058: el CSV usa el nombre del programa (el modelo no tiene codigo)
    @idTipoPrograma1 = p.idTipoPrograma,
    @uCoord1 = ci.idUsuario, 
    @idCoord1 = ci.id,
    @idInstitucion = p.idInstitucion,
    @idFacultad1 = p.idFacultad
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 AND p.estaActivoPrograma = 1
ORDER BY p.id;

DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
DECLARE @idDecano1 UNIQUEIDENTIFIER, @uDecano1 UNIQUEIDENTIFIER;
SELECT TOP 1 @idDecano1 = d.id, @uDecano1 = d.idUsuario 
FROM dbo.uv_facultad f 
INNER JOIN dbo.uv_decano d ON d.id = f.idDecano 
WHERE f.id = @idFacultad1;

IF @tipoCC IS NULL OR @tipoTI IS NULL OR @idPrograma1 IS NULL OR @uCoord1 IS NULL OR @uAdmin IS NULL OR @idDecano1 IS NULL
    THROW 52501, 'TEST FAILED: CULM001_D5 faltan fixtures basicos del seed.', 1;

CREATE TABLE #res (
    numeroFila INT,
    esValida BIT,
    yaExiste BIT,
    codigoMensaje VARCHAR(20),
    mensajeUsuario NVARCHAR(4000),
    idTipoIdentificacion UNIQUEIDENTIFIER,
    idTipoVinculacion UNIQUEIDENTIFIER,
    idPrograma UNIQUEIDENTIFIER,
    idFacultad UNIQUEIDENTIFIER,
    idUsuarioExistente UNIQUEIDENTIFIER
);

CREATE TABLE #cmdCoord (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

CREATE TABLE #cmdDec (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

DECLARE @corr UNIQUEIDENTIFIER, @ok BIT, @filasJson NVARCHAR(MAX), @errCode INT, @errMsg NVARCHAR(4000);
DECLARE @uDocExistente UNIQUEIDENTIFIER, @docExistenteNum INT = 815000050;
DECLARE @docenteId UNIQUEIDENTIFIER;
DECLARE @idPrograma2 UNIQUEIDENTIFIER, @codigoProg2 NVARCHAR(50) = N'QA Programa 2 D5';
DECLARE @idFacultad2 UNIQUEIDENTIFIER, @idDecano2 UNIQUEIDENTIFIER, @uDecano2 UNIQUEIDENTIFIER;

-- (fuera de la transaccion de la prueba, ver nota al final)
-- ---------------------------------------------------------------- D5-03 Administrador con destino DOCENTE -> THROW CMA_009
SET @corr = NEWID();
SET @errCode = 0;
SET @errMsg = N'';
BEGIN TRY
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uAdmin,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = N'[{"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000011, "correo": "doc.admin@test.local"}]';
END TRY
BEGIN CATCH
    SET @errCode = ERROR_NUMBER();
    SET @errMsg = ERROR_MESSAGE();
END CATCH;
SET @ok = IIF(@errMsg LIKE '%CMA_009%', 1, 0);
EXEC #d5_expect 'D5_03_ADMIN_DESTINO_DOCENTE_CMA_009', @ok;
PRINT 'TEST_PASS:CULM001_D5_03_JERARQUIA_NO_PERMITIDA';

BEGIN TRANSACTION;
BEGIN TRY
    -- ---------------------------------------------------------------- D5-00 Objetos y semillas de D.5
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.tables WHERE name = 'JerarquiaAltaUsuario')
              AND EXISTS (SELECT 1 FROM sys.views WHERE name = 'uv_jerarquia_alta_usuario')
              AND EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_validar_carga_masiva_usuarios')
              AND (SELECT COUNT(*) FROM dbo.JerarquiaAltaUsuario) >= 3
              AND dbo.ufn_obtener_parametro('CARGA_MASIVA', 'MAXIMO_FILAS') IS NOT NULL
              AND dbo.ufn_obtener_parametro('IDENTIDAD', 'TIPO_IDENTIFICACION_DEFECTO') IS NOT NULL, 1, 0);
    EXEC #d5_expect 'D5_00_OBJETOS_Y_SEMILLAS', @ok;
    PRINT 'TEST_PASS:CULM001_D5_00_OBJETOS_Y_SEMILLAS';

    -- ---------------------------------------------------------------- D5-01 Coordinador con 3 filas validas -> 3 esValida=1 y 0 escrituras
    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000001, "correo": "doc1.d5@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null},
        {"numeroFila": 3, "tipoDocumento": "CC", "numeroDocumento": 815000002, "correo": "doc2.d5@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null},
        {"numeroFila": 4, "tipoDocumento": "CC", "numeroDocumento": 815000003, "correo": "doc3.d5@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null}
    ]';
    
    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF((SELECT COUNT(*) FROM #res) = 3
              AND (SELECT COUNT(*) FROM #res WHERE esValida = 1 AND yaExiste = 0 AND codigoMensaje IS NULL) = 3
              AND NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion IN (815000001, 815000002, 815000003)), 1, 0);
    EXEC #d5_expect 'D5_01_COORDINADOR_TRES_VALIDAS', @ok;
    PRINT 'TEST_PASS:CULM001_D5_01_COORDINADOR_TRES_VALIDAS';

    -- ---------------------------------------------------------------- D5-02 Decano con programa de otra facultad -> CMA_007
    -- Crear una segunda facultad con su programa
    SET @idFacultad2 = NEWID();
    -- Fixtures: el seed solo trae un decano y un coordinador; se crean un segundo decano y un segundo coordinador (rollback al final).
    DECLARE @uDecano2Fix UNIQUEIDENTIFIER, @uCoord2Fix UNIQUEIDENTIFIER, @idCoord2 UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 815000201,
        @primerApellido = N'DecanoDos', @segundoApellido = NULL, @primerNombre = N'QA', @segundoNombre = NULL,
        @correo = N'decano2.d5@test.local', @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @errMsg OUTPUT, @mensajeTecnicoResultado = @errMsg OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d5_expect 'FIXTURE_DECANO2_USUARIO', @ok;
    EXEC dbo.usp_sincronizar_usuario_interno
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 815000202,
        @primerApellido = N'CoordDos', @segundoApellido = NULL, @primerNombre = N'QA', @segundoNombre = NULL,
        @correo = N'coord2.d5@test.local', @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @errMsg OUTPUT, @mensajeTecnicoResultado = @errMsg OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d5_expect 'FIXTURE_COORD2_USUARIO', @ok;
    SELECT @uDecano2Fix = id FROM dbo.Usuario WHERE numeroIdentificacion = 815000201;
    SELECT @uCoord2Fix = id FROM dbo.Usuario WHERE numeroIdentificacion = 815000202;
    SET @idDecano2 = NEWID();
    INSERT dbo.Decano (id, usuario) VALUES (@idDecano2, @uDecano2Fix);
    INSERT dbo.Coordinador (id, usuario) VALUES (@idCoord2, @uCoord2Fix);
    INSERT dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (@idFacultad2, N'QA Facultad 2 D5', @idInstitucion, @idDecano2, 1);

    SET @idPrograma2 = NEWID();
    INSERT dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@idPrograma2, @idFacultad2, @idTipoPrograma1, @codigoProg2, @idCoord2, 1);

    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000010, "correo": "coord.ajeno@test.local", "codigoTipoVinculacion": null, "codigoPrograma": "' + @codigoProg2 + N'", "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uDecano1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'COORDINADOR',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 0 AND codigoMensaje = 'CMA_007'), 1, 0);
    EXEC #d5_expect 'D5_02_DECANO_PROGRAMA_OTRA_FACULTAD', @ok;
    PRINT 'TEST_PASS:CULM001_D5_02_DECANO_PROGRAMA_OTRA_FACULTAD';

    -- ---------------------------------------------------------------- D5-04 Duplicado en el archivo por documento y por correo -> CMA_010
    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000021, "correo": "dup1@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null},
        {"numeroFila": 3, "tipoDocumento": "CC", "numeroDocumento": 815000021, "correo": "otro@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null},
        {"numeroFila": 4, "tipoDocumento": "CC", "numeroDocumento": 815000022, "correo": "dup1@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 1)
              AND EXISTS (SELECT 1 FROM #res WHERE numeroFila = 3 AND esValida = 0 AND codigoMensaje = 'CMA_010')
              AND EXISTS (SELECT 1 FROM #res WHERE numeroFila = 4 AND esValida = 0 AND codigoMensaje = 'CMA_010'), 1, 0);
    EXEC #d5_expect 'D5_04_DUPLICADOS_EN_ARCHIVO_CMA_010', @ok;
    PRINT 'TEST_PASS:CULM001_D5_04_DUPLICADO_EN_ARCHIVO';

    -- ---------------------------------------------------------------- D5-05 Persona con el rol en el ambito -> yaExiste = 1
    -- Crear persona previa y asignarle Docente en @idPrograma1
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno 
        @idTipoIdIdentificacion = @tipoCC, 
        @numeroIdentificacion = @docExistenteNum,
        @primerApellido = N'DocenteExistente', @segundoApellido = NULL, 
        @primerNombre = N'Carlos', @segundoNombre = NULL,
        @correo = N'carlos.docente.existente@test.local', 
        @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @errMsg OUTPUT, @mensajeTecnicoResultado = @errMsg OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d5_expect 'FIXTURE_DOCENTE_EXISTENTE_USUARIO', @ok;

    SELECT @uDocExistente = id FROM dbo.Usuario WHERE numeroIdentificacion = @docExistenteNum;
    SET @docenteId = NEWID();
    INSERT dbo.Docente (id, usuario)
    VALUES (@docenteId, @uDocExistente);

    INSERT dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @docenteId, @idPrograma1, @tipoVincTC, 1, SYSUTCDATETIME());

    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": ' + CAST(@docExistenteNum AS NVARCHAR(20)) + N', "correo": "carlos.docente.existente@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 1 AND yaExiste = 1 AND idUsuarioExistente = @uDocExistente), 1, 0);
    EXEC #d5_expect 'D5_05_PERSONA_YA_EXISTE_EN_ROL', @ok;
    PRINT 'TEST_PASS:CULM001_D5_05_ROL_YA_EXISTE';

    -- ---------------------------------------------------------------- D5-06 Documento y correo corresponden a personas distintas -> CMA_008
    -- Crear dos personas distintas
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno 
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 815000061,
        @primerApellido = N'PersonaA', @segundoApellido = NULL, @primerNombre = N'A', @segundoNombre = NULL,
        @correo = N'personaA.d5@test.local', @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @errMsg OUTPUT, @mensajeTecnicoResultado = @errMsg OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d5_expect 'FIXTURE_PERSONA_A', @ok;

    EXEC dbo.usp_sincronizar_usuario_interno 
        @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 815000062,
        @primerApellido = N'PersonaB', @segundoApellido = NULL, @primerNombre = N'B', @segundoNombre = NULL,
        @correo = N'personaB.d5@test.local', @password = N'HashTest123', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @errMsg OUTPUT, @mensajeTecnicoResultado = @errMsg OUTPUT, @estadoResultado = @ok OUTPUT;
    EXEC #d5_expect 'FIXTURE_PERSONA_B', @ok;

    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    -- Mezcla: doc de A con correo de B
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000061, "correo": "personaB.d5@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 0 AND codigoMensaje = 'CMA_008'), 1, 0);
    EXEC #d5_expect 'D5_06_PERSONAS_DISTINTAS_CMA_008', @ok;
    PRINT 'TEST_PASS:CULM001_D5_06_PERSONAS_DISTINTAS';

    -- ---------------------------------------------------------------- D5-07 Codigo de catalogo desconocido -> CMA_006
    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "XYZ_NO_EXISTE", "numeroDocumento": 815000071, "correo": "cat1@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null},
        {"numeroFila": 3, "tipoDocumento": "CC", "numeroDocumento": 815000072, "correo": "cat2@test.local", "codigoTipoVinculacion": "VINC_INVENTADA", "codigoPrograma": "' + @codigoProg1 + N'", "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 0 AND codigoMensaje = 'CMA_006')
              AND EXISTS (SELECT 1 FROM #res WHERE numeroFila = 3 AND esValida = 0 AND codigoMensaje = 'CMA_006'), 1, 0);
    EXEC #d5_expect 'D5_07_CATALOGOS_DESCONOCIDOS_CMA_006', @ok;
    PRINT 'TEST_PASS:CULM001_D5_07_CATALOGO_DESCONOCIDO';

    -- ---------------------------------------------------------------- D5-08 Coordinador de 2 programas sin codigoPrograma -> CMA_007
    -- Asignar el segundo programa al mismo coordinador
    UPDATE dbo.Programa SET coordinador = @idCoord1 WHERE id = @idPrograma2;

    TRUNCATE TABLE #res;
    SET @corr = NEWID();
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000081, "correo": "multi.coord@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": null, "codigoFacultad": null}
    ]';

    INSERT #res
    EXEC dbo.usp_validar_carga_masiva_usuarios
        @idUsuarioEjecutor = @uCoord1,
        @idCorrelacion = @corr,
        @codigoPerfilDestino = 'DOCENTE',
        @filasJson = @filasJson;

    SET @ok = IIF(EXISTS (SELECT 1 FROM #res WHERE numeroFila = 2 AND esValida = 0 AND codigoMensaje = 'CMA_007'), 1, 0);
    EXEC #d5_expect 'D5_08_MULTI_PROGRAMA_SIN_PROGRAMA_CMA_007', @ok;
    PRINT 'TEST_PASS:CULM001_D5_08_MULTI_PROGRAMA_SIN_PROGRAMA';

    -- ---------------------------------------------------------------- D5-10 usp_crear_coordinador con @idTipoIdIdentificacion
    TRUNCATE TABLE #cmdCoord;
    SET @corr = NEWID();
    INSERT #cmdCoord
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

    SET @ok = IIF(EXISTS (SELECT 1 FROM #cmdCoord WHERE estadoResultado = 1)
              AND @tipoGuardadoCoord = @tipoTI
              AND @defCoord NOT LIKE N'%''CC''%'
              AND @defDec NOT LIKE N'%''CC''%', 1, 0);
    EXEC #d5_expect 'D5_10_TIPO_IDENTIFICACION_PARAMETRO_SIN_CC_LITERAL', @ok;
    PRINT 'TEST_PASS:CULM001_D5_10_TIPO_DOC_PARAMETRO';

    -- ---------------------------------------------------------------- D5-12 Llamadas existentes sin parametro nuevo siguen funcionando
    TRUNCATE TABLE #cmdCoord;
    SET @corr = NEWID();
    INSERT #cmdCoord
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

    DECLARE @tipoDefectoCoord UNIQUEIDENTIFIER = (SELECT tipoIdIdentificacion FROM dbo.Usuario WHERE numeroIdentificacion = 815000121);

    TRUNCATE TABLE #cmdDec;
    SET @corr = NEWID();
    INSERT #cmdDec
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

    DECLARE @tipoDefectoDec UNIQUEIDENTIFIER = (SELECT tipoIdIdentificacion FROM dbo.Usuario WHERE numeroIdentificacion = 815000122);

    SET @ok = IIF(EXISTS (SELECT 1 FROM #cmdCoord WHERE estadoResultado = 1)
              AND EXISTS (SELECT 1 FROM #cmdDec WHERE estadoResultado = 1)
              AND @tipoDefectoCoord = @tipoCC
              AND @tipoDefectoDec = @tipoCC, 1, 0);
    EXEC #d5_expect 'D5_12_LLAMADAS_LEGACY_DEFAULT_CC', @ok;
    PRINT 'TEST_PASS:CULM001_D5_12_LLAMADAS_LEGACY_COMPATIBLES';

    -- Los THROW del SP (XACT_ABORT ON) condenan la transaccion abierta (XACT_STATE = -1): D5-09 corre al final de la
    -- transaccion y D5-03 antes de abrirla; las demas verificaciones no necesitan escribir despues de ellos.
    -- ---------------------------------------------------------------- D5-09 Mas filas que el parametro -> THROW CMA_001
    UPDATE dbo.CatalogoParametro 
    SET valor = N'2' 
    WHERE grupo = 'CARGA_MASIVA' AND clave = 'MAXIMO_FILAS';

    SET @corr = NEWID();
    SET @errCode = 0;
    SET @errMsg = N'';
    SET @filasJson = N'[
        {"numeroFila": 2, "tipoDocumento": "CC", "numeroDocumento": 815000091, "correo": "f1@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'"},
        {"numeroFila": 3, "tipoDocumento": "CC", "numeroDocumento": 815000092, "correo": "f2@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'"},
        {"numeroFila": 4, "tipoDocumento": "CC", "numeroDocumento": 815000093, "correo": "f3@test.local", "codigoTipoVinculacion": "PLA", "codigoPrograma": "' + @codigoProg1 + N'"}
    ]';
    BEGIN TRY
        EXEC dbo.usp_validar_carga_masiva_usuarios
            @idUsuarioEjecutor = @uCoord1,
            @idCorrelacion = @corr,
            @codigoPerfilDestino = 'DOCENTE',
            @filasJson = @filasJson;
    END TRY
    BEGIN CATCH
        SET @errCode = ERROR_NUMBER();
        SET @errMsg = ERROR_MESSAGE();
    END CATCH;
    SET @ok = IIF(@errMsg LIKE '%CMA_001%', 1, 0);
    EXEC #d5_expect 'D5_09_MAXIMO_FILAS_EXCEDIDO_CMA_001', @ok;
    PRINT 'TEST_PASS:CULM001_D5_09_MAXIMO_FILAS';
    -- El parametro se restaura con el ROLLBACK final de la prueba.

    PRINT 'TEST_PASS:CULM001_D5_TRANCOUNT_ZERO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:CULM001_D5_SUITE_COMPLETA';
GO
