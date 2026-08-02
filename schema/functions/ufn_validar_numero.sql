USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    FUNCTION [dbo].[ufn_validar_numero] (
    @numero BIGINT
)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 0;

    -- 1. Validar que no sea nulo, ni menor o igual a cero (ID por defecto)
    IF @numero IS NULL OR @numero <= 0
    BEGIN
        SET @resultado = 0;
    END
    -- 2. Validar longitud (m?nimo 6, m?ximo 10 d?gitos para identificaci?n)
    ELSE IF LEN(CAST(@numero AS VARCHAR(20))) < 6 OR LEN(CAST(@numero AS VARCHAR(20))) > 10
    BEGIN
        SET @resultado = 0;
    END
    ELSE
    BEGIN
        SET @resultado = 1;
    END

    RETURN @resultado;
END;
GO
