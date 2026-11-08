USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-15): todo objeto programable de dbo (vistas, SP, funciones) se recompila sin errores despues de las
-- migraciones 17/18 y de cada down. Cursor sobre sys.sql_modules, sin los de esquema enlazado. No modifica datos.
SET NOCOUNT ON;
PRINT 'TEST START: test_culm001_b2nm_compilacion';

DECLARE @errores TABLE (objeto NVARCHAR(300), error NVARCHAR(2000));
DECLARE @obj NVARCHAR(300), @tipo CHAR(2);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(QUOTENAME(SCHEMA_NAME(o.schema_id)), N'.', QUOTENAME(o.name)), o.type
    FROM sys.objects o
    INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
    WHERE o.schema_id = SCHEMA_ID(N'dbo') AND o.type IN ('V', 'P', 'IF', 'FN', 'TF') AND m.is_schema_bound = 0
    ORDER BY o.type, o.name;
OPEN c;
FETCH NEXT FROM c INTO @obj, @tipo;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sys.sp_refreshsqlmodule @name = @obj;
    END TRY
    BEGIN CATCH
        INSERT INTO @errores VALUES (@obj, ERROR_MESSAGE());
    END CATCH
    FETCH NEXT FROM c INTO @obj, @tipo;
END
CLOSE c; DEALLOCATE c;

IF EXISTS (SELECT 1 FROM @errores)
BEGIN
    SELECT objeto, error FROM @errores ORDER BY objeto;
    THROW 53810, 'TEST FAILED: B2NM-15 hay objetos que no compilan (ver el resultset).', 1;
END
PRINT 'TEST_PASS:CULM001_B2NM_COMPILACION';
GO
