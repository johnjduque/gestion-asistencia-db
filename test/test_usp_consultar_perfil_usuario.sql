USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_perfil_usuario (HU006)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion ORDER BY tipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @tvCat         UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL OR @tvCat IS NULL
    THROW 54100, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID(), @u3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoId, 340000001, N'Perez', N'Gomez', N'Ana', N'Maria', CONCAT(N'qa.hu006.1.', @sufijo, N'@test.local'), 1, 1, N'HashBackend_Secreto'),
           (@u2, @tipoId, 340000002, N'Sin', N'', N'Vinculos', N'', CONCAT(N'qa.hu006.2.', @sufijo, N'@test.local'), 0, 1, N'HashBackend_Secreto'),
           (@u3, @tipoId, 340000003, N'Otro', N'', N'Decano', N'', CONCAT(N'qa.hu006.3.', @sufijo, N'@test.local'), 1, 1, N'HashBackend_Secreto');

    -- U1 tiene todos los roles: estudiante en P1, docente en P1 (activo) y P2 (inactivo), coordinador de P2,
    -- decano de F y administrador de la institucion. U2 no tiene vinculos.
    DECLARE @est UNIQUEIDENTIFIER = NEWID(), @doc UNIQUEIDENTIFIER = NEWID(), @coo UNIQUEIDENTIFIER = NEWID(), @dec UNIQUEIDENTIFIER = NEWID();
    DECLARE @dec3 UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @c3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, @u1), (@dec3, @u3);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA HU006 F ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@coo, @u1, @f), (@c3, @u3, @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p1, @f, @tipoProg, CONCAT(N'A HU006 P1 ', @sufijo), @c3, 1), (@p2, @f, @tipoProg, CONCAT(N'B HU006 P2 ', @sufijo), @coo, 1);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@est, @u1);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @est, @p1);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc, @u1);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc) VALUES
        (NEWID(), @doc, @p1, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @doc, @p2, @tvCat, 0, SYSUTCDATETIME());
    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES (NEWID(), @u1, @idInstitucion);

    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    CREATE TABLE #p (n INT IDENTITY(1,1), idUsuario UNIQUEIDENTIFIER, codigoTipoIdentificacion NVARCHAR(5), nombreTipoIdentificacion NVARCHAR(50),
        numeroIdentificacion INT, primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), primerApellido NVARCHAR(50), segundoApellido NVARCHAR(50),
        nombreCompleto NVARCHAR(400), correo NVARCHAR(100), correoConfirmado BIT, estaActivoUsuario BIT, rolVinculo VARCHAR(20),
        idEntidadVinculo UNIQUEIDENTIFIER, nombreEntidadVinculo NVARCHAR(50), detalleVinculo NVARCHAR(50), estaActivoVinculo BIT);

    -- P-01: datos personales y un vinculo por rol, en orden estudiante, docente, coordinador, decano, administrador.
    INSERT INTO #p (idUsuario, codigoTipoIdentificacion, nombreTipoIdentificacion, numeroIdentificacion, primerNombre, segundoNombre, primerApellido,
        segundoApellido, nombreCompleto, correo, correoConfirmado, estaActivoUsuario, rolVinculo, idEntidadVinculo, nombreEntidadVinculo, detalleVinculo, estaActivoVinculo)
    EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @c, @idUsuarioEjecutor = @u1;
    IF (SELECT COUNT(*) FROM #p) <> 6
        THROW 54101, 'TEST FAILED: P-01 se esperaban 6 vinculos de U1.', 1;
    IF EXISTS (SELECT 1 FROM #p WHERE idUsuario <> @u1 OR numeroIdentificacion <> 340000001 OR nombreCompleto <> N'Ana Maria Perez Gomez'
               OR correoConfirmado <> 1 OR estaActivoUsuario <> 1)
        THROW 54102, 'TEST FAILED: P-01 datos personales.', 1;
    IF (SELECT rolVinculo FROM #p WHERE n = 1) <> 'ESTUDIANTE' OR (SELECT idEntidadVinculo FROM #p WHERE n = 1) <> @p1
       OR (SELECT rolVinculo FROM #p WHERE n = 2) <> 'DOCENTE' OR (SELECT idEntidadVinculo FROM #p WHERE n = 2) <> @p1
       OR (SELECT estaActivoVinculo FROM #p WHERE n = 2) <> 1
       OR (SELECT rolVinculo FROM #p WHERE n = 3) <> 'DOCENTE' OR (SELECT idEntidadVinculo FROM #p WHERE n = 3) <> @p2
       OR (SELECT estaActivoVinculo FROM #p WHERE n = 3) <> 0
       OR (SELECT rolVinculo FROM #p WHERE n = 4) <> 'COORDINADOR' OR (SELECT idEntidadVinculo FROM #p WHERE n = 4) <> @p2
       OR (SELECT rolVinculo FROM #p WHERE n = 5) <> 'DECANO' OR (SELECT idEntidadVinculo FROM #p WHERE n = 5) <> @f
       OR (SELECT rolVinculo FROM #p WHERE n = 6) <> 'ADMINISTRADOR' OR (SELECT idEntidadVinculo FROM #p WHERE n = 6) <> @idInstitucion
        THROW 54103, 'TEST FAILED: P-01 orden o entidad de los vinculos.', 1;
    IF (SELECT detalleVinculo FROM #p WHERE n = 2) <> (SELECT nombre FROM dbo.TipoVinculacion WHERE id = @tvCat)
       OR (SELECT detalleVinculo FROM #p WHERE n = 1) <> CONCAT(N'QA HU006 F ', @sufijo)
        THROW 54104, 'TEST FAILED: P-01 detalle del vinculo.', 1;
    PRINT 'TEST_PASS:HU006_PERFIL_DATOS_VINCULOS';

    -- P-02: usuario sin vinculos => una fila con el vinculo en NULL; solo ve SU perfil (U3 no aparece).
    TRUNCATE TABLE #p;
    INSERT INTO #p (idUsuario, codigoTipoIdentificacion, nombreTipoIdentificacion, numeroIdentificacion, primerNombre, segundoNombre, primerApellido,
        segundoApellido, nombreCompleto, correo, correoConfirmado, estaActivoUsuario, rolVinculo, idEntidadVinculo, nombreEntidadVinculo, detalleVinculo, estaActivoVinculo)
    EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @c, @idUsuarioEjecutor = @u2;
    IF (SELECT COUNT(*) FROM #p) <> 1 OR EXISTS (SELECT 1 FROM #p WHERE rolVinculo IS NOT NULL OR idUsuario <> @u2 OR correoConfirmado <> 0
               OR nombreCompleto <> N'Vinculos Sin')
        THROW 54105, 'TEST FAILED: P-02 usuario sin vinculos.', 1;
    PRINT 'TEST_PASS:HU006_PERFIL_SIN_VINCULOS';

    -- P-03: usuario inexistente => 0 filas; ejecutor nulo => VAL_001.
    TRUNCATE TABLE #p;
    INSERT INTO #p (idUsuario, codigoTipoIdentificacion, nombreTipoIdentificacion, numeroIdentificacion, primerNombre, segundoNombre, primerApellido,
        segundoApellido, nombreCompleto, correo, correoConfirmado, estaActivoUsuario, rolVinculo, idEntidadVinculo, nombreEntidadVinculo, detalleVinculo, estaActivoVinculo)
    EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @c, @idUsuarioEjecutor = @c;
    IF (SELECT COUNT(*) FROM #p) <> 0
        THROW 54106, 'TEST FAILED: P-03 usuario inexistente debe devolver 0 filas.', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 54107, 'TEST FAILED: P-03 ejecutor nulo (esperaba VAL_001).', 1;
    PRINT 'TEST_PASS:HU006_PERFIL_VALIDACIONES';

    IF @@TRANCOUNT <> 1 THROW 54198, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 54199, 'TEST FAILED: test_usp_consultar_perfil_usuario dejo transacciones abiertas.', 1;
PRINT '==================================================';
PRINT 'TEST END: test_usp_consultar_perfil_usuario (HU006)';
PRINT '==================================================';
GO
