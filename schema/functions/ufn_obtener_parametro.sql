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
    DECLARE @valorDefecto NVARCHAR(MAX);

    SELECT 
        @valor = valor,
        @valorDefecto = valorDefecto
    FROM dbo.Parametro
    WHERE grupo = TRIM(@p_grupo) 
      AND clave = TRIM(@p_clave) 
      AND estaActivo = 1;

    RETURN ISNULL(@valor, @valorDefecto);
END;
GO
