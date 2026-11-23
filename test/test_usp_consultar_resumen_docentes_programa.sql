USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_consultar_resumen_docentes_programa (HU095)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL
    THROW 53800, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 9
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
        VALUES (@uid, @tipoId, 320000000 + ABS(CHECKSUM(NEWID()) % 99999999), CONCAT(N'Apellido', CHAR(64 + @i)), N'QA', CONCAT(N'Nombre', CHAR(64 + @i)), N'X',
                CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, IIF(@i = 8, 0, 1));
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END
    -- n: 1 decano, 2 coordinador P1, 3 coordinador P2, 4..8 docentes D1..D5 (D5 = usuario 8 inactivo), 9 coordinador sin programa
    DECLARE @uDec UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 1), @uC1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 2),
            @uC2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 3);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @dec UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, @uDec);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA HU095 ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c1, @uC1, @f), (@c2, @uC2, @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p1, @f, @tipoProg, CONCAT(N'HU095 P1 ', @sufijo), @c1, 1), (@p2, @f, @tipoProg, CONCAT(N'HU095 P2 ', @sufijo), @c2, 1);

    CREATE TABLE #d (k NVARCHAR(2), id UNIQUEIDENTIFIER, n INT);
    INSERT INTO #d VALUES (N'D1', NEWID(), 4), (N'D2', NEWID(), 5), (N'D3', NEWID(), 6), (N'D4', NEWID(), 7), (N'D5', NEWID(), 8);
    INSERT INTO dbo.Docente (id, usuario) SELECT d.id, u.id FROM #d d INNER JOIN #u u ON u.n = d.n;
    -- P1: D1 activo, D2 vinculo inactivo, D3 activo, D5 con usuario inactivo (cuenta inactiva => inactivo).
    -- P2: D4 activo (no debe contar en P1). MEJORAS-SERGIO-2026-11-18: el resumen ya no se agrupa por tipo de vinculacion.
    INSERT INTO dbo.DocentePrograma (id, docente, programa, estado, fechaVinculacionUtc)
    SELECT NEWID(), d.id, v.programa, v.estado, SYSUTCDATETIME()
    FROM (VALUES (N'D1', @p1, 1), (N'D2', @p1, 0), (N'D3', @p1, 1), (N'D5', @p1, 1), (N'D4', @p2, 1))
         AS v (k, programa, estado)
    INNER JOIN #d d ON d.k = v.k;

    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    CREATE TABLE #r (totalActivos INT, totalInactivos INT);

    -- R-01: una sola fila con los activos e inactivos del programa del coordinador.
    INSERT INTO #r EXEC dbo.usp_consultar_resumen_docentes_programa @idUsuarioEjecutor = @uC1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #r) <> 1
        THROW 53801, 'TEST FAILED: R-01 el resumen debe ser una sola fila.', 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE totalActivos = 2 AND totalInactivos = 2)
        THROW 53802, 'TEST FAILED: R-01 esperaba 2 activos y 2 inactivos (vinculo inactivo y cuenta inactiva; P2 no cuenta).', 1;
    PRINT 'TEST_PASS:HU095_RESUMEN_PROGRAMA';

    -- R-02: el coordinador de P2 solo ve su programa.
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_resumen_docentes_programa @idUsuarioEjecutor = @uC2, @idCorrelacion = @c;
    IF (SELECT SUM(totalActivos + totalInactivos) FROM #r) <> 1
       OR NOT EXISTS (SELECT 1 FROM #r WHERE totalActivos = 1)
        THROW 53806, 'TEST FAILED: R-02 el coordinador de P2 solo ve el vinculo de P2.', 1;
    PRINT 'TEST_PASS:HU095_RESUMEN_AMBITO';

    -- R-03: ejecutor que no coordina (decano) => KPI_001; ejecutor nulo => VAL_001.
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_resumen_docentes_programa @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=KPI_001|%'
        THROW 53807, 'TEST FAILED: R-03 decano (esperaba KPI_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_resumen_docentes_programa @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 53808, 'TEST FAILED: R-03 ejecutor nulo (esperaba VAL_001).', 1;
    PRINT 'TEST_PASS:HU095_RESUMEN_VALIDACIONES';

    IF @@TRANCOUNT <> 1 THROW 53898, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53899, 'TEST FAILED: test_usp_consultar_resumen_docentes_programa dejo transacciones abiertas.', 1;
PRINT '==================================================';
PRINT 'TEST END: test_usp_consultar_resumen_docentes_programa (HU095)';
PRINT '==================================================';
GO
