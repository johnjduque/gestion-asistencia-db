USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    FUNCTION [dbo].[ufn_validar_correo] (
    @p_correo NVARCHAR(320)
)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 0;

    -- Validamos que no sea nulo, que no est? vac?o y que cumpla un patr?n m?s real
    IF @p_correo IS NOT NULL 
       AND LTRIM(RTRIM(@p_correo)) <> ''
       AND @p_correo LIKE '%_@%_._%'          -- Al menos un caracter antes y despu?s de @, y un punto
       AND @p_correo NOT LIKE '%@%@%'        -- No permite doble arroba
       AND @p_correo NOT LIKE '%..%'          -- No permite puntos seguidos
       AND CHARINDEX(' ', @p_correo) = 0      -- No permite espacios
    BEGIN
        SET @resultado = 1;
    END

    RETURN @resultado;
END
GO
