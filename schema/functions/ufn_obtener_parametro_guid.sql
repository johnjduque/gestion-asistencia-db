USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_parametro_guid] (
    @p_valor UNIQUEIDENTIFIER,
    @p_grupo VARCHAR(100),
    @p_claveDefecto VARCHAR(100)
)
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    IF @p_valor IS NOT NULL
        RETURN @p_valor;

    RETURN TRY_CAST(dbo.ufn_obtener_parametro(@p_grupo, @p_claveDefecto) AS UNIQUEIDENTIFIER);
END;
GO
