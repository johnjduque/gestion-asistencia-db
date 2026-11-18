USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- FIX-CIERRE-001 (decision de producto 2026-11-16): cierre masivo sin caer al periodo mas reciente.
--   FIX001_CIE_01  usp_ejecutar_cierre_masivo_periodo: codigo que no existe -> PER_001, no cierra ni audita nada (antes cerraba el periodo mas reciente)
--   FIX001_CIE_02  codigo nulo, vacio o solo espacios -> GEN_002, no cierra ni audita nada (antes cerraba el periodo mas reciente)
--   FIX001_CIE_03  codigo valido (por nombre y por codigo numerico) -> sigue cerrando ESE periodo y solo ese (auditoria con su id)
-- Todo corre en UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_fix_cierre_001_cierre_masivo';
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
    -- ======================================================= Cierre masivo del periodo
    -- Periodo propio y antiguo (anio 1999): el "mas reciente" del seed es otro, por lo que el caso viejo cerraba el periodo equivocado.
    DECLARE @idPeriodoQa UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idPeriodoQa, @inst, N'QA-FIX001-1999', 991999, '1999-01-10', '1999-06-10', 1999);

    SELECT @act = COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @idEstadoActivo;
    SELECT @aud = COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO';

    -- FIX001_CIE_01: codigo que no existe
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = N'QA-NO-EXISTE-2999', @idActor = N'QA_FIX001', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF((SELECT COUNT(*) FROM #fix1c) = 1
                  AND EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_001|%')
                  AND (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @idEstadoActivo) = @act
                  AND (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO') = @aud, 1, 0);
    IF @ok <> 1 THROW 54911, 'TEST FAILED FIX001_CIE_01: un codigo de periodo inexistente debe responder PER_001 sin cerrar ni auditar nada.', 1;
    PRINT 'TEST_PASS:FIX001_CIE_01_CODIGO_INEXISTENTE';

    -- FIX001_CIE_02: codigo nulo, vacio o solo espacios
    SET @n = 0;
    DECLARE @codigos TABLE (orden INT, codigo NVARCHAR(50));
    INSERT @codigos VALUES (1, NULL), (2, N''), (3, N'   ');
    DECLARE @orden INT = 1, @codigoProbado NVARCHAR(50);
    WHILE @orden <= 3
    BEGIN
        SELECT @codigoProbado = codigo FROM @codigos WHERE orden = @orden;
        SET @corr = NEWID();
        DELETE FROM #fix1c;
        INSERT #fix1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @codigoProbado, @idActor = N'QA_FIX001', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
        IF (SELECT COUNT(*) FROM #fix1c) <> 1 OR NOT EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
            THROW 54912, 'TEST FAILED FIX001_CIE_02: un codigo de periodo nulo o vacio debe responder GEN_002.', 1;
        SET @orden += 1;
    END
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @idEstadoActivo) <> @act
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO') <> @aud
        THROW 54913, 'TEST FAILED FIX001_CIE_02: un codigo nulo o vacio no debe cerrar ni auditar nada.', 1;
    PRINT 'TEST_PASS:FIX001_CIE_02_CODIGO_VACIO';

    -- FIX001_CIE_03: codigo valido, por nombre y por codigo numerico: cierra ese periodo (vacio, no cambia matriculas de otros) y audita su id
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = N'QA-FIX001-1999', @idActor = N'QA_FIX001', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND resourceId = CONVERT(NVARCHAR(50), @idPeriodoQa))
                  AND (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @idEstadoActivo) = @act, 1, 0);
    IF @ok <> 1 THROW 54914, 'TEST FAILED FIX001_CIE_03: el cierre por nombre debe cerrar solo el periodo indicado y auditarlo.', 1;
    -- VAL-pendientes-john PRU-15: el primer cierre marco el periodo como cerrado y un segundo cierre responderia PER_009; se reabre
    -- (solo el fixture) para probar tambien la resolucion por codigo numerico.
    UPDATE dbo.PeriodoAcademico SET fechaCierreUtc = NULL WHERE id = @idPeriodoQa;
    SET @corr = NEWID();
    DELETE FROM #fix1c;
    INSERT #fix1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = N'991999', @idActor = N'QA_FIX001', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix1c WHERE estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND resourceId = CONVERT(NVARCHAR(50), @idPeriodoQa))
                  AND (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @idEstadoActivo) = @act, 1, 0);
    IF @ok <> 1 THROW 54915, 'TEST FAILED FIX001_CIE_03: el cierre por codigo numerico debe cerrar solo el periodo indicado y auditarlo.', 1;
    PRINT 'TEST_PASS:FIX001_CIE_03_CODIGO_VALIDO';

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
PRINT 'TEST_PASS:FIX001_CIE_TRANCOUNT_ZERO';
GO
