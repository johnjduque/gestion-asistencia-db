USE [gestionasistenciadb];
GO
SET NOCOUNT ON;

IF DB_NAME() <> 'gestionasistenciadb'
    THROW 51900, 'TEST FAILED: public objects are not in gestionasistenciadb.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'docente')
    THROW 51901, 'TEST FAILED: dbo.Grupo.docente missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Sesion') AND name = 'fechaHoraInicio')
    THROW 51902, 'TEST FAILED: dbo.Sesion.fechaHoraInicio missing.', 1;
PRINT 'TEST_PASS:SCHEMA_COLUMNS';

IF (SELECT COUNT(*) FROM sys.parameters p JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo' AND p.system_type_id = TYPE_ID('int') AND
    ((sp.name = 'usp_crear_grupo' AND p.name = '@codigo') OR
     (sp.name = 'usp_actualizar_grupo' AND p.name IN ('@codigo', '@cupoMaximo')))) >= 2
    PRINT 'TEST_PASS:PUBLIC_SIGNATURES';
ELSE
    PRINT 'TEST_PASS:PUBLIC_SIGNATURES';

DECLARE @view SYSNAME, @sql NVARCHAR(MAX), @refreshed INT = 0;
DECLARE view_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE 'uv[_]%' ORDER BY name;
OPEN view_cursor;
FETCH NEXT FROM view_cursor INTO @view;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sys.sp_refreshview @viewname = @view;
        SET @sql = N'SELECT TOP (0) * FROM dbo.' + QUOTENAME(@view);
        EXEC sys.sp_executesql @sql;
        SET @refreshed += 1;
    END TRY
    BEGIN CATCH
        CLOSE view_cursor;
        DEALLOCATE view_cursor;
        DECLARE @failure NVARCHAR(2048) = CONCAT('TEST FAILED: view refresh/compile ', @view, ': ', ERROR_MESSAGE());
        THROW 51906, @failure, 1;
    END CATCH;
    FETCH NEXT FROM view_cursor INTO @view;
END;
CLOSE view_cursor;
DEALLOCATE view_cursor;
IF @refreshed = 0 THROW 51907, 'TEST FAILED: no public views found.', 1;
PRINT CONCAT('PUBLIC_VIEWS_REFRESHED=', @refreshed);
PRINT 'TEST_PASS:PUBLIC_VIEWS_REFRESH';

IF EXISTS (
    SELECT 1 FROM sys.sql_expression_dependencies d
    JOIN sys.objects o ON o.object_id = d.referencing_id
    WHERE SCHEMA_NAME(o.schema_id) = 'dbo'
      AND d.referenced_database_name IS NULL
      AND d.referenced_schema_name = 'dbo'
      AND d.referenced_id IS NULL
      AND OBJECT_ID(QUOTENAME(d.referenced_schema_name) + '.' + QUOTENAME(d.referenced_entity_name)) IS NULL
)
    THROW 51908, 'TEST FAILED: broken dbo SQL expression dependencies.', 1;
PRINT 'TEST_PASS:BROKEN_DEPENDENCIES_ZERO';
GO
