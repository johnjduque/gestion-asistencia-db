USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    FUNCTION [dbo].[ufn_validar_password] (
    @p_password NVARCHAR(MAX),
    @p_numeroIdentificacionDefecto INT
)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 0;
    DECLARE @passwordString NVARCHAR(MAX) = LTRIM(RTRIM(ISNULL(@p_password, '')));
    DECLARE @idString NVARCHAR(MAX) = CAST(@p_numeroIdentificacionDefecto AS NVARCHAR(MAX));

    -- 1. Regla de Oro: Si es el valor por defecto, ES V?LIDO
    IF @passwordString = @idString
    BEGIN
        SET @resultado = 1;
    END
    -- 2. Si no es el defecto, validar condiciones de seguridad
    ELSE
    BEGIN
        IF LEN(@passwordString) >= 8                          -- M?nimo 8 caracteres
           AND @passwordString LIKE '%[0-9]%'                -- Al menos un n?mero
           AND @passwordString LIKE '%[A-Z]%'                -- Al menos una may?scula
           AND @passwordString LIKE '%[a-z]%'                -- Al menos una min?scula
           AND @passwordString LIKE '%[!@#$%^&*()_+-=%]%'    -- Al menos un car?cter especial
        BEGIN
            SET @resultado = 1;
        END
    END

    RETURN @resultado;
END
GO
