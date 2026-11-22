USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_ident002_activacion_cuentas (IDENT-002)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- A00: objetos y mensajes del contrato (falla en RED si faltan)
    -- =========================================================================
    IF OBJECT_ID(N'dbo.usp_consultar_reenvio_activacion_cuenta', N'P') IS NULL
        THROW 56000, 'TEST FAILED ACT-A00: SP usp_consultar_reenvio_activacion_cuenta no existe.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('VCE_009', 'ACT_001', 'ACT_002') AND estaActivo = 1) <> 3
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('VCE_009', 'ACT_001', 'ACT_002') AND estaActivo = 1) <> 3
        THROW 56003, 'TEST FAILED ACT-A00: faltan mensajes VCE_009, ACT_001 o ACT_002 (usuario/tecnico).', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.database_permissions p
                   WHERE p.major_id = OBJECT_ID(N'dbo.usp_consultar_reenvio_activacion_cuenta')
                     AND p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
                     AND p.permission_name = 'EXECUTE' AND p.state = 'G')
        THROW 56004, 'TEST FAILED ACT-A00: rol_asistencias_runtime no tiene EXECUTE sobre el SP de reenvio.', 1;
    PRINT 'TEST_PASS:IDENT002_ACT_A00';

    -- =========================================================================
    -- Fixtures: una cuenta pendiente de activacion y un administrador ejecutor
    -- =========================================================================
    CREATE TABLE #reenvio (idUsuario UNIQUEIDENTIFIER NULL);
    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL
    );
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a INNER JOIN dbo.Usuario u ON u.id = a.usuario AND u.estado = 1);
    DECLARE @estudianteSinPerfil UNIQUEIDENTIFIER = (SELECT TOP 1 e.usuario FROM dbo.Estudiante e
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Docente d WHERE d.usuario = e.usuario)
          AND NOT EXISTS (SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = e.usuario)
          AND NOT EXISTS (SELECT 1 FROM dbo.Decano dc WHERE dc.usuario = e.usuario)
          AND NOT EXISTS (SELECT 1 FROM dbo.Administrador ad WHERE ad.usuario = e.usuario));
    IF @admin IS NULL OR @estudianteSinPerfil IS NULL
        THROW 56009, 'TEST FAILED ACT-F00: faltan datos semilla (administrador activo o estudiante sin otro rol).', 1;

    DECLARE @pendiente UNIQUEIDENTIFIER = NEWID();
    DECLARE @numero INT = 1990000000 + ABS(CHECKSUM(NEWID())) % 9000000;
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@pendiente, @tipoCC, @numero, N'ACTIVACION', N'PRUEBA', N'IDENT', N'DOS',
            LOWER(CONCAT(N'ident002.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@uco.edu.co')), 0, 1);

    -- =========================================================================
    -- ACT-R01: el administrador obtiene el usuario de una cuenta pendiente
    -- =========================================================================
    PRINT '-> ACT-R01: reenvio permitido para cuenta pendiente';
    INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_activacion_cuenta
        @idUsuario = @pendiente, @idUsuarioEjecutor = @admin, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #reenvio WHERE idUsuario = @pendiente) <> 1
        THROW 56010, 'TEST FAILED ACT-R01: el administrador debio obtener el usuario pendiente.', 1;
    PRINT 'TEST_PASS:IDENT002_ACT_R01';

    -- =========================================================================
    -- ACT-R02: un ejecutor sin perfil ADMINISTRADOR/DECANO/COORDINADOR es rechazado
    -- =========================================================================
    PRINT '-> ACT-R02: RBAC del ejecutor';
    DECLARE @capturado NVARCHAR(4000) = N'';
    BEGIN TRY
        DELETE FROM #reenvio;
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_activacion_cuenta
            @idUsuario = @pendiente, @idUsuarioEjecutor = @estudianteSinPerfil, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado = N'' OR (SELECT COUNT(*) FROM #reenvio) <> 0
        THROW 56011, 'TEST FAILED ACT-R02: un estudiante no debe poder reenviar activaciones.', 1;
    PRINT 'TEST_PASS:IDENT002_ACT_R02';

    -- =========================================================================
    -- ACT-R03: espera minima entre envios (VCE_003)
    -- =========================================================================
    PRINT '-> ACT-R03: espera minima';
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_emitir_token_verificacion_correo
        @idUsuario = @pendiente, @tokenHash = 0x1111111111111111111111111111111111111111111111111111111111111111, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #r) <> 1
        THROW 56012, 'TEST FAILED ACT-R03: no se pudo emitir el token del fixture.', 1;
    SET @capturado = N'';
    BEGIN TRY
        DELETE FROM #reenvio;
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_activacion_cuenta
            @idUsuario = @pendiente, @idUsuarioEjecutor = @admin, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=VCE_003%'
        THROW 56013, 'TEST FAILED ACT-R03: el reenvio inmediato debio rechazarse con VCE_003.', 1;
    PRINT 'TEST_PASS:IDENT002_ACT_R03';

    -- =========================================================================
    -- ACT-R04: cuenta ya activada (ACT_002) y usuario inexistente (VCE_007)
    -- =========================================================================
    PRINT '-> ACT-R04: cuenta activa e inexistente';
    UPDATE dbo.Usuario SET correoConfirmado = 1 WHERE id = @pendiente;
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_activacion_cuenta
            @idUsuario = @pendiente, @idUsuarioEjecutor = @admin, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=ACT_002%'
        THROW 56014, 'TEST FAILED ACT-R04: una cuenta activa debio rechazarse con ACT_002.', 1;
    SET @capturado = N'';
    BEGIN TRY
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_activacion_cuenta
            @idUsuario = @corr, @idUsuarioEjecutor = @admin, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=VCE_007%'
        THROW 56015, 'TEST FAILED ACT-R04: un usuario inexistente debio rechazarse con VCE_007.', 1;
    PRINT 'TEST_PASS:IDENT002_ACT_R04';

    DROP TABLE #reenvio;
    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 56099, 'TEST FAILED ACT-G01: test_ident002_activacion_cuentas dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:IDENT002_ACT_G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_ident002_activacion_cuentas (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_IDENT002_ACTIVACION_CUENTAS';
GO
