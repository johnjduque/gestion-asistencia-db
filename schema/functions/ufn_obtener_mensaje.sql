USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_mensaje] (
    @p_codigo NVARCHAR(50),
    @p_tipo NVARCHAR(20),
    @p_entidad NVARCHAR(100)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @plantilla NVARCHAR(MAX);

    SELECT @plantilla = CASE WHEN UPPER(TRIM(@p_tipo)) = 'USUARIO' THEN contenidoUsuario ELSE contenidoTecnico END
    FROM dbo.Mensaje
    WHERE codigo = TRIM(@p_codigo) AND tipo = TRIM(@p_tipo) AND estaActivo = 1;

    RETURN REPLACE(ISNULL(@plantilla, ''), '{entidad}', ISNULL(@p_entidad, ''));
END;
GO
