USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- FIX-CIERRE-001 (decision de producto 2026-11-16): alta de decano con facultad por id o nombre exacto, sin LIKE.
--   FIX001_DEC_01  usp_crear_decano: nombre de facultad aproximado (antes LIKE '%x%') -> FAC_001 y no crea el decano
--   FIX001_DEC_02  comodin '%' como nombre -> FAC_001 (antes coincidia con cualquier facultad)
--   FIX001_DEC_03  nombre inexistente -> FAC_001 y no crea el decano
--   FIX001_DEC_04  id de facultad inexistente -> FAC_001 y no crea el decano
--   FIX001_DEC_05  nombre exacto con otra capitalizacion -> asigna esa facultad
--   FIX001_DEC_06  id de facultad existente -> asigna esa facultad
--   FIX001_DEC_07  sin facultad (id y nombre nulos) -> crea el decano sin facultad (HU178) y no toca ninguna facultad
-- Todo corre en UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_fix_cierre_001_decano';
GO

DECLARE @uAdmin UNIQUEIDENTIFIER, @inst UNIQUEIDENTIFIER;
SELECT TOP 1 @uAdmin = a.usuario, @inst = a.institucion FROM dbo.Administrador a ORDER BY a.id;
IF @uAdmin IS NULL OR @inst IS NULL
    THROW 54901, 'TEST FAILED FIX001: falta un administrador en el seed.', 1;

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @hash NVARCHAR(500) = N'HashBackend_QaFix001_1234567890';
DECLARE @corr UNIQUEIDENTIFIER, @n INT, @aud INT, @act INT, @ok BIT;
DECLARE @codInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @idEstadoActivo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codInscrita ORDER BY id);

IF OBJECT_ID(N'tempdb..#fix1c') IS NOT NULL DROP TABLE #fix1c;
CREATE TABLE #fix1c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

BEGIN TRANSACTION;
BEGIN TRY
    -- ======================================================= Alta de decano
    DECLARE @uOtro UNIQUEIDENTIFIER = NEWID(), @decOtro UNIQUEIDENTIFIER = NEWID(), @facQa UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uOtro, @tipoCC, 917000001, N'Previo', N'Qa', N'Decano', N'Fix001', N'decano.previo.qa.fix001@uco.edu.co', 1, 1, @hash);
    INSERT dbo.Decano (id, usuario) VALUES (@decOtro, @uOtro);
    INSERT dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@facQa, N'QA Fix001 Facultad Exacta', @inst, @decOtro, 1);

    DECLARE @decanos INT = (SELECT COUNT(*) FROM dbo.Decano), @usuarios INT = (SELECT COUNT(*) FROM dbo.Usuario);

    -- FIX001_DEC_01: nombre aproximado (subcadena de la facultad real)
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000002, @primerNombre = N'Aprox', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.aprox.qa.fix001@uco.edu.co', @idFacultad = NULL, @nombreFacultad = N'QA Fix001 Facultad',
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos AND (SELECT COUNT(*) FROM dbo.Usuario) = @usuarios
                  AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @facQa AND decano = @decOtro), 1, 0);
    IF @ok <> 1 THROW 54921, 'TEST FAILED FIX001_DEC_01: un nombre de facultad aproximado debe responder FAC_001 y no crear el decano.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_01_NOMBRE_APROXIMADO';

    -- FIX001_DEC_02: el comodin no es un nombre
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000003, @primerNombre = N'Comodin', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.comodin.qa.fix001@uco.edu.co', @idFacultad = NULL, @nombreFacultad = N'%',
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos AND (SELECT COUNT(*) FROM dbo.Usuario) = @usuarios, 1, 0);
    IF @ok <> 1 THROW 54922, 'TEST FAILED FIX001_DEC_02: el comodin % no debe resolver una facultad.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_02_COMODIN';

    -- FIX001_DEC_03: nombre inexistente
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000004, @primerNombre = N'Inexistente', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.inexistente.qa.fix001@uco.edu.co', @idFacultad = NULL, @nombreFacultad = N'Facultad que no existe QA',
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos AND (SELECT COUNT(*) FROM dbo.Usuario) = @usuarios, 1, 0);
    IF @ok <> 1 THROW 54923, 'TEST FAILED FIX001_DEC_03: un nombre de facultad inexistente debe responder FAC_001 y no crear el decano.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_03_NOMBRE_INEXISTENTE';

    -- FIX001_DEC_04: id de facultad inexistente
    DECLARE @idFacInexistente UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000005, @primerNombre = N'IdMalo', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.idmalo.qa.fix001@uco.edu.co', @idFacultad = @idFacInexistente, @nombreFacultad = NULL,
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos AND (SELECT COUNT(*) FROM dbo.Usuario) = @usuarios, 1, 0);
    IF @ok <> 1 THROW 54924, 'TEST FAILED FIX001_DEC_04: un id de facultad inexistente debe responder FAC_001 y no crear el decano.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_04_ID_INEXISTENTE';

    -- FIX001_DEC_05: nombre exacto con otra capitalizacion
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000006, @primerNombre = N'Exacto', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.exacto.qa.fix001@uco.edu.co', @idFacultad = NULL, @nombreFacultad = N'QA FIX001 FACULTAD EXACTA',
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 1)
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos + 1
                  AND EXISTS (SELECT 1 FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano INNER JOIN dbo.Usuario u ON u.id = d.usuario
                              WHERE f.id = @facQa AND u.correo = N'decano.exacto.qa.fix001@uco.edu.co'), 1, 0);
    IF @ok <> 1 THROW 54925, 'TEST FAILED FIX001_DEC_05: el nombre exacto (insensible a mayusculas) debe asignar esa facultad.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_05_NOMBRE_EXACTO';

    -- FIX001_DEC_06: id de facultad existente
    SET @decanos = (SELECT COUNT(*) FROM dbo.Decano);
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000007, @primerNombre = N'PorId', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.porid.qa.fix001@uco.edu.co', @idFacultad = @facQa, @nombreFacultad = NULL,
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 1)
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos + 1
                  AND EXISTS (SELECT 1 FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano INNER JOIN dbo.Usuario u ON u.id = d.usuario
                              WHERE f.id = @facQa AND u.correo = N'decano.porid.qa.fix001@uco.edu.co'), 1, 0);
    IF @ok <> 1 THROW 54926, 'TEST FAILED FIX001_DEC_06: un id de facultad existente debe asignar esa facultad.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_06_ID_EXISTENTE';

    -- FIX001_DEC_07: sin facultad (HU178): crea el decano sin facultad y no toca ninguna
    SET @decanos = (SELECT COUNT(*) FROM dbo.Decano);
    DECLARE @titularAntes UNIQUEIDENTIFIER = (SELECT decano FROM dbo.Facultad WHERE id = @facQa);
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 917000008, @primerNombre = N'SinFac', @segundoNombre = N'', @primerApellido = N'Decano',
        @segundoApellido = N'Fix001', @correo = N'decano.sinfac.qa.fix001@uco.edu.co', @idFacultad = NULL, @nombreFacultad = NULL,
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 1)
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @decanos + 1
                  AND NOT EXISTS (SELECT 1 FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano INNER JOIN dbo.Usuario u ON u.id = d.usuario
                                  WHERE u.correo = N'decano.sinfac.qa.fix001@uco.edu.co')
                  AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @facQa AND decano = @titularAntes), 1, 0);
    IF @ok <> 1 THROW 54927, 'TEST FAILED FIX001_DEC_07: sin facultad se crea el decano sin facultad y no se toca ninguna.', 1;
    PRINT 'TEST_PASS:FIX001_DEC_07_SIN_FACULTAD';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 54999, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

IF @@TRANCOUNT <> 0
    THROW 54990, 'TEST FAILED FIX001_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:FIX001_DEC_TRANCOUNT_ZERO';
GO
