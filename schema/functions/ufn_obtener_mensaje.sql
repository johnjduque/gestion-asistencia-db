USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  FUNCTION [dbo].[ufn_obtener_mensaje] (
    @p_codigo NVARCHAR(50),
    @p_tipo NVARCHAR(20),
    @p_entidad NVARCHAR(100)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @plantilla NVARCHAR(MAX);

    SELECT @plantilla = contenido
    FROM dbo.Mensaje
    WHERE codigo = @p_codigo AND tipo = @p_tipo;

    RETURN REPLACE(@plantilla, '{entidad}', @p_entidad);
END;
GO
