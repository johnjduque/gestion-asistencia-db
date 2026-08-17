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
    DECLARE @plantilla NVARCHAR(4000);
    DECLARE @resultado NVARCHAR(4000);
    DECLARE @codigo VARCHAR(100) = TRIM(ISNULL(@p_codigo, ''));
    DECLARE @tipo VARCHAR(20) = UPPER(TRIM(ISNULL(@p_tipo, '')));

    IF @tipo = 'USUARIO'
    BEGIN
        SELECT @plantilla = contenido
        FROM dbo.CatalogoMensajeUsuario
        WHERE codigo = @codigo AND estaActivo = 1;
    END
    ELSE
    BEGIN
        SELECT @plantilla = contenido
        FROM dbo.CatalogoMensajeTecnico
        WHERE codigo = @codigo AND estaActivo = 1;
    END

    SET @resultado = ISNULL(@plantilla, '');

    IF @p_entidad IS NOT NULL
    BEGIN
        IF CHARINDEX('{entidad}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{entidad}', @p_entidad);
        ELSE IF CHARINDEX('{0}', @resultado) > 0
            SET @resultado = REPLACE(@resultado, '{0}', @p_entidad);
        ELSE IF CHARINDEX('{}', @resultado) > 0
            SET @resultado = STUFF(@resultado, CHARINDEX('{}', @resultado), 2, @p_entidad);
    END

    SET @resultado = REPLACE(@resultado, '{entidad}', '');
    SET @resultado = REPLACE(@resultado, '{0}', '');
    SET @resultado = REPLACE(@resultado, '{}', '');

    RETURN @resultado;
END;
GO
