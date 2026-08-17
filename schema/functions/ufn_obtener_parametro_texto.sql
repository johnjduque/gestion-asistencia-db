USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_parametro_texto] (
    @p_valor NVARCHAR(MAX),
    @p_grupo VARCHAR(100),
    @p_claveDefecto VARCHAR(100)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @p_valor IS NOT NULL
        RETURN TRIM(@p_valor);

    RETURN TRIM(dbo.ufn_obtener_parametro(@p_grupo, @p_claveDefecto));
END;
GO
