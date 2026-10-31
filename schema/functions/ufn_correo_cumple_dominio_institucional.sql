USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: 1 solo si el correo tiene exactamente un '@', parte local no vacia y dominio IGUAL al configurado
-- (incluye el '@', p. ej. '@uco.edu.co'). Comparacion insensible a mayusculas y sin espacios laterales. Fail-closed:
-- NULL, dominio vacio o sin '@' devuelven 0. No acepta subdominios ni sufijos adicionales.
CREATE OR ALTER FUNCTION [dbo].[ufn_correo_cumple_dominio_institucional] (
    @correo  NVARCHAR(255),
    @dominio NVARCHAR(255)
)
RETURNS BIT
AS
BEGIN
    DECLARE @c NVARCHAR(255) = LOWER(LTRIM(RTRIM(@correo)));
    DECLARE @d NVARCHAR(255) = LOWER(LTRIM(RTRIM(@dominio)));

    IF @c IS NULL OR @d IS NULL OR LEN(@d) < 2 OR LEFT(@d, 1) <> N'@' OR CHARINDEX(N'@', @d, 2) > 0
        RETURN 0;

    IF LEN(@c) - LEN(REPLACE(@c, N'@', N'')) <> 1
        RETURN 0;

    DECLARE @posicion INT = CHARINDEX(N'@', @c);
    IF @posicion <= 1
        RETURN 0;

    IF SUBSTRING(@c, @posicion, LEN(@c) - @posicion + 1) <> @d
        RETURN 0;

    RETURN 1;
END;
GO
