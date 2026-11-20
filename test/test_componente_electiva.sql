USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- COMP-ELE (migracion 60, docs/work-items/COMP-ELE-componente-electiva/PLAN.md): componente de formacion "electivas" (ELE).
--   COMP_ELE_01  la fila ELE existe una sola vez, con el nombre 'electivas', y uv_componente la expone.
--   COMP_ELE_02  usp_resolver_area_componente_asignatura_interno resuelve ELE por codigo y por nombre (sin distinguir
--                mayusculas ni espacios extremos), igual que BAS/INS/ESP.
-- ============================================================================
DECLARE @idEle UNIQUEIDENTIFIER = '9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E';
IF (SELECT COUNT(1) FROM dbo.Componente WHERE codigo = N'ELE') <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.Componente WHERE id = @idEle AND codigo = N'ELE' AND nombre = N'electivas')
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_componente WHERE id = @idEle)
    THROW 52950, 'TEST FAILED: COMP_ELE_01 la fila ELE no existe, esta repetida o uv_componente no la expone.', 1;
PRINT 'TEST_PASS:COMP_ELE_01_FILA_ELE';
GO

DECLARE @idEle UNIQUEIDENTIFIER = '9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E';
DECLARE @valores TABLE (n INT, valor NVARCHAR(100));
INSERT @valores VALUES (1, N'ELE'), (2, N' ele '), (3, N'electivas'), (4, N'ELECTIVAS');
DECLARE @n INT = 1, @valor NVARCHAR(100), @idArea UNIQUEIDENTIFIER, @idComp UNIQUEIDENTIFIER,
        @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID(), @msg NVARCHAR(400);
WHILE @n <= 4
BEGIN
    SELECT @valor = valor FROM @valores WHERE n = @n;
    SELECT @idArea = NULL, @idComp = NULL, @mu = N'', @mt = N'', @ok = 1;
    EXEC dbo.usp_resolver_area_componente_asignatura_interno @area = NULL, @componente = @valor, @obligatorios = 0,
         @idCorrelacion = @corr, @idArea = @idArea OUTPUT, @idComponente = @idComp OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @idComp IS NULL OR @idComp <> @idEle
    BEGIN
        SET @msg = N'TEST FAILED: COMP_ELE_02 no resolvio el componente con el valor [' + @valor + N'].';
        THROW 52951, @msg, 1;
    END
    SET @n += 1;
END
PRINT 'TEST_PASS:COMP_ELE_02_RESOLVER_ELE';
GO
