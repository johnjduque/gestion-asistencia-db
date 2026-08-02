USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    FUNCTION [dbo].[ufn_validar_texto] (
    @p_texto NVARCHAR(MAX)
)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 1;

    -- 1. Validaci?n de Vac?o o Nulo
    -- Si el valor es exactamente '', la funci?n devuelve 0
    IF @p_texto IS NULL OR LTRIM(RTRIM(@p_texto)) = ''
    BEGIN
        SET @resultado = 0;
    END
    -- 2. Validaci?n de caracteres permitidos (Incluye n?meros 0-9)
    -- Si encuentra algo que NO sea letras, n?meros, tildes o espacios, devuelve 0
    ELSE IF PATINDEX('%[^A-Za-z????????????0-9 ]%', @p_texto) > 0
    BEGIN
        SET @resultado = 0;
    END

    RETURN @resultado;
END;
GO
