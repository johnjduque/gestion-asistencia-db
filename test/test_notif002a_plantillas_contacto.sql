USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_notif002a_plantillas_contacto (NOTIF-002A)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Verificar existencia de los objetos de contacto de NOTIF-002A (falla en RED si faltan). Las plantillas se retiraron con la migracion 71.
    -- =========================================================================
    IF OBJECT_ID(N'dbo.usp_consultar_contacto_notificacion', N'P') IS NULL
        THROW 54003, 'TEST FAILED DB-C01: SP dbo.usp_consultar_contacto_notificacion no existe.', 1;

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    CREATE TABLE #r_err (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- =========================================================================
    -- DB-C01 & DB-C02: usp_consultar_contacto_notificacion (activos vs inactivos/inexistentes)
    -- =========================================================================
    PRINT '-> DB-C01 / DB-C02: consulta de contacto para usuarios activos, inactivos e inexistentes';
    DECLARE @idTipoDoc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
    DECLARE @uActivo1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uActivo2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uInactivo UNIQUEIDENTIFIER = NEWID();
    DECLARE @uInexistente UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES
        (@uActivo1, @idTipoDoc, 189000001, N'ApellidoUno', N'SegUno', N'NombreUno', N'', N'activo1.notif002a@uco.edu.co', 1, 1),
        (@uActivo2, @idTipoDoc, 189000002, N'ApellidoDos', N'SegDos', N'NombreDos', N'', N'activo2.notif002a@uco.edu.co', 0, 1),
        (@uInactivo, @idTipoDoc, 189000003, N'ApellidoTres', N'SegTres', N'NombreTres', N'', N'inactivo.notif002a@uco.edu.co', 1, 0);

    DECLARE @jsonContactos NVARCHAR(MAX) = CONCAT(
        N'["', CONVERT(NVARCHAR(36), @uActivo1),
        N'","', CONVERT(NVARCHAR(36), @uActivo2),
        N'","', CONVERT(NVARCHAR(36), @uInactivo),
        N'","', CONVERT(NVARCHAR(36), @uInexistente), N'"]'
    );

    -- Verificar con tabla temporal sobre usp_consultar_contacto_notificacion_interno
    CREATE TABLE #contactos (
        idUsuario        UNIQUEIDENTIFIER,
        correo           NVARCHAR(100),
        correoConfirmado BIT
    );
    INSERT INTO #contactos
    EXEC dbo.usp_consultar_contacto_notificacion_interno @usuariosJson = @jsonContactos;

    IF (SELECT COUNT(*) FROM #contactos) <> 2
        THROW 54060, 'TEST FAILED DB-C01/C02: deberia devolver exactamente los 2 usuarios habilitados.', 1;

    IF NOT EXISTS (SELECT 1 FROM #contactos WHERE idUsuario = @uActivo1 AND correo = N'activo1.notif002a@uco.edu.co' AND correoConfirmado = 1)
       OR NOT EXISTS (SELECT 1 FROM #contactos WHERE idUsuario = @uActivo2 AND correo = N'activo2.notif002a@uco.edu.co' AND correoConfirmado = 0)
        THROW 54061, 'TEST FAILED DB-C01: datos de correo o correoConfirmado no coinciden.', 1;

    IF EXISTS (SELECT 1 FROM #contactos WHERE idUsuario IN (@uInactivo, @uInexistente))
        THROW 54062, 'TEST FAILED DB-C02: usuario inhabilitado o inexistente aparecio en el resultado.', 1;

    -- Invocar el SP publico
    SET @corr = NEWID();
    EXEC dbo.usp_consultar_contacto_notificacion
        @usuariosJson = @jsonContactos,
        @idCorrelacion = @corr;

    PRINT 'TEST_PASS:DB-C01';
    PRINT 'TEST_PASS:DB-C02';

    -- =========================================================================
    -- DB-C03 & DB-C04: @usuariosJson invalido/vacio/>100/no-UUID -> NTF_001; @idCorrelacion nulo -> CORR_001
    -- =========================================================================
    PRINT '-> DB-C03 / DB-C04: validaciones de @usuariosJson e @idCorrelacion';
    DECLARE @101Guids NVARCHAR(MAX) = N'[';
    DECLARE @idx INT = 1;
    WHILE @idx <= 101
    BEGIN
        SET @101Guids = CONCAT(@101Guids, CASE WHEN @idx > 1 THEN N',' ELSE N'' END, N'"', CONVERT(NVARCHAR(36), NEWID()), N'"');
        SET @idx += 1;
    END
    SET @101Guids = CONCAT(@101Guids, N']');

    DECLARE @jsonsInvalidos TABLE (caso VARCHAR(30), j NVARCHAR(MAX));
    INSERT INTO @jsonsInvalidos VALUES
        ('NULL', NULL),
        ('EMPTY', N''),
        ('EMPTY_ARR', N'[]'),
        ('NOT_JSON', N'no-es-json'),
        ('JSON_OBJ', N'{"id":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}'),
        ('OVER_100', @101Guids),
        ('BAD_UUID', N'["no-es-un-uuid"]'),
        ('MIXED_BAD_UUID', N'["' + CONVERT(NVARCHAR(36), NEWID()) + N'","uuid-malo"]');

    DECLARE @jBad NVARCHAR(MAX), @casoJ VARCHAR(30);
    DECLARE curJ CURSOR LOCAL FAST_FORWARD FOR SELECT caso, j FROM @jsonsInvalidos;
    OPEN curJ;
    FETCH NEXT FROM curJ INTO @casoJ, @jBad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #r_err;
        SET @corr = NEWID();
        INSERT INTO #r_err
        EXEC dbo.usp_consultar_contacto_notificacion
            @usuariosJson = @jBad,
            @idCorrelacion = @corr;

        IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
            THROW 54070, 'TEST FAILED DB-C03/C04: no rechazo @usuariosJson invalido con NTF_001.', 1;

        FETCH NEXT FROM curJ INTO @casoJ, @jBad;
    END
    CLOSE curJ;
    DEALLOCATE curJ;

    TRUNCATE TABLE #r_err;
    INSERT INTO #r_err
    EXEC dbo.usp_consultar_contacto_notificacion
        @usuariosJson = @jsonContactos,
        @idCorrelacion = NULL;

    IF NOT EXISTS (SELECT 1 FROM #r_err WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 54071, 'TEST FAILED DB-C03: no rechazo @idCorrelacion nulo con CORR_001.', 1;

    PRINT 'TEST_PASS:DB-C03';
    PRINT 'TEST_PASS:DB-C04';

    -- =========================================================================
    -- DB-G01: rol_asistencias_runtime puede ejecutar el SP publico de contacto y no el interno
    -- =========================================================================
    PRINT '-> DB-G01: permisos de rol_asistencias_runtime sobre el SP de contacto y denegacion del interno';
    CREATE USER [notif002a_runtime_tmp] WITHOUT LOGIN;
    ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [notif002a_runtime_tmp];

    DECLARE @execContacto INT = 0, @execInternoDenegado INT = 0;
    BEGIN TRY
        EXECUTE AS USER = 'notif002a_runtime_tmp';

        SET @execContacto  = HAS_PERMS_BY_NAME(N'dbo.usp_consultar_contacto_notificacion', N'OBJECT', N'EXECUTE');

        BEGIN TRY
            EXEC dbo.usp_consultar_contacto_notificacion_interno @usuariosJson = N'[]';
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 229 SET @execInternoDenegado = 1;
        END CATCH;

        REVERT;
    END TRY
    BEGIN CATCH
        IF USER_NAME() = 'notif002a_runtime_tmp' REVERT;
        THROW;
    END CATCH;

    IF @execContacto <> 1 OR @execInternoDenegado <> 1
        THROW 54100, 'TEST FAILED DB-G01: permisos de rol_asistencias_runtime incorrectos en NOTIF-002A.', 1;

    PRINT 'TEST_PASS:DB-G01';

    DROP TABLE #contactos;
    DROP TABLE #r_err;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF USER_NAME() <> 'dbo' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

-- =========================================================================
-- DB-G02: @@TRANCOUNT = 0 al terminar; sin transacciones huerfanas
-- =========================================================================
IF @@TRANCOUNT <> 0
    THROW 54199, 'TEST FAILED DB-G02: test_notif002a_plantillas_contacto dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:DB-G02';
PRINT '==================================================';
PRINT 'TEST PASS: test_notif002a_plantillas_contacto (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_NOTIF002A_PLANTILLAS_CONTACTO';
GO
