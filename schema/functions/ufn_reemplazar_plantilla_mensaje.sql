USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_reemplazar_plantilla_mensaje] (
    @p_plantilla NVARCHAR(4000),
    @p_param1 NVARCHAR(500) = NULL,
    @p_param2 NVARCHAR(500) = NULL,
    @p_param3 NVARCHAR(500) = NULL
)
RETURNS NVARCHAR(4000)
AS
BEGIN
    IF @p_plantilla IS NULL OR TRIM(@p_plantilla) = ''
        RETURN '';

    DECLARE @resultado NVARCHAR(4000) = @p_plantilla;

    -- Reemplazo de parámetro 1
    IF @p_param1 IS NOT NULL
    BEGIN
        IF CHARINDEX('{0}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{0}', @p_param1);
        ELSE IF CHARINDEX('{entidad}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{entidad}', @p_param1);
        ELSE IF CHARINDEX('{}', @resultado) > 0
            SET @resultado = STUFF(@resultado, CHARINDEX('{}', @resultado), 2, @p_param1);
    END

    -- Reemplazo de parámetro 2
    IF @p_param2 IS NOT NULL
    BEGIN
        IF CHARINDEX('{1}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{1}', @p_param2);
        ELSE IF CHARINDEX('{}', @resultado) > 0
            SET @resultado = STUFF(@resultado, CHARINDEX('{}', @resultado), 2, @p_param2);
    END

    -- Reemplazo de parámetro 3
    IF @p_param3 IS NOT NULL
    BEGIN
        IF CHARINDEX('{2}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{2}', @p_param3);
        ELSE IF CHARINDEX('{}', @resultado) > 0
            SET @resultado = STUFF(@resultado, CHARINDEX('{}', @resultado), 2, @p_param3);
    END

    -- Limpieza de comodines sobrantes no provistos
    SET @resultado = REPLACE(@resultado, '{entidad}', '');
    SET @resultado = REPLACE(@resultado, '{0}', '');
    SET @resultado = REPLACE(@resultado, '{1}', '');
    SET @resultado = REPLACE(@resultado, '{2}', '');

    RETURN @resultado;
END;
GO
