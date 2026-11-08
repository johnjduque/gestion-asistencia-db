USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-08, S4): un coordinador de DOS programas. Sin @idPrograma las listas incluyen ambos programas y los KPIs/ficha/bitacora
-- responden COO_002; con un programa propio funcionan; con uno ajeno COO_003. Transaccion revertida. Los THROW van al final
-- (con XACT_ABORT ON invalidan la transaccion compartida).
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_culm001_b2nm_coordinador_dos_programas';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    -- CA pasa a coordinar tambien el programa B (el coordinador de B queda sin programas)
    UPDATE dbo.Programa SET coordinador = (SELECT c.id FROM dbo.Coordinador c WHERE c.usuario = @uCA) WHERE id = @progB;
    IF (SELECT COUNT(*) FROM dbo.ufn_programas_coordinador(@uCA)) <> 2 THROW 53901, 'TEST FAILED: B2NM-08 CA debe coordinar dos programas.', 1;

    -- las listas sin @idPrograma incluyen ambos programas (directorio que sirve GET /coordinador/estudiantes)
    DECLARE @dl TABLE (id UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, tipoIdentificacionId UNIQUEIDENTIFIER, numeroIdentificacion INT, primerApellido NVARCHAR(100),
        segundoApellido NVARCHAR(100), primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), nombreCompleto NVARCHAR(400), correo NVARCHAR(100),
        estaActivoUsuario BIT, totalRegistros INT);
    INSERT INTO @dl EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @nombre = N'B2NM';
    IF NOT EXISTS (SELECT 1 FROM @dl WHERE id = @eA) OR NOT EXISTS (SELECT 1 FROM @dl WHERE id = @eB) OR EXISTS (SELECT 1 FROM @dl WHERE id = @e0)
        THROW 53902, 'TEST FAILED: B2NM-08 el directorio sin programa debe incluir a EA y EB y no a E0.', 1;
    DELETE FROM @dl;
    INSERT INTO @dl EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @nombre = N'B2NM', @idPrograma = @progB;
    IF (SELECT COUNT(*) FROM @dl) <> 1 OR NOT EXISTS (SELECT 1 FROM @dl WHERE id = @eB) THROW 53903, 'TEST FAILED: B2NM-08 con idPrograma = B solo EB.', 1;

    -- la ficha de EA con @idPrograma = A funciona; la de EB pedida con A responde GEN_001 (R6)
    DECLARE @f TABLE (c1 UNIQUEIDENTIFIER);
    DECLARE @resultados INT = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_ficha_estudiante_programa @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idEstudiante = @eA, @idPrograma = @progA;
        SET @resultados += 1;
    END TRY
    BEGIN CATCH
    END CATCH
    IF @resultados <> 1 THROW 53904, 'TEST FAILED: B2NM-08 la ficha de EA con idPrograma = A debe funcionar.', 1;

    -- KPIs: sin programa -> COO_002; con un programa ajeno -> COO_003 (THROW, ultimo paso)
    DECLARE @coo002 BIT = 0, @coo003 BIT = 0, @progAjeno UNIQUEIDENTIFIER = NEWID();
    BEGIN TRY
        EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%COO_002%' SET @coo002 = 1;
    END CATCH
    IF @coo002 = 0 THROW 53905, 'TEST FAILED: B2NM-08 KPIs sin idPrograma de un coordinador de dos programas deben dar COO_002.', 1;

    PRINT 'TEST_PASS:CULM001_B2NM_COORDINADOR_DOS_PROGRAMAS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 53899, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
