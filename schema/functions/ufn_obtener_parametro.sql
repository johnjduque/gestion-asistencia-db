USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_parametro] (
    @p_grupo VARCHAR(100),
    @p_clave VARCHAR(100)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @valor NVARCHAR(MAX);

    SELECT @valor = valor
    FROM dbo.Parametro
    WHERE grupo = @p_grupo AND clave = @p_clave;

    RETURN @valor;
END;
GO
