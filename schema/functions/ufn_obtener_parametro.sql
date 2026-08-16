USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Asegurar existencia de vista previa para evitar errores de compilación por orden de despliegue
IF OBJECT_ID('dbo.uv_parametro', 'V') IS NULL
BEGIN
    EXEC('CREATE VIEW dbo.uv_parametro AS SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS id, CAST('' '' AS VARCHAR(100)) AS grupo, CAST('' '' AS VARCHAR(100)) AS clave, CAST('' '' AS NVARCHAR(MAX)) AS valor, CAST(''STRING'' AS VARCHAR(20)) AS tipoDato, CAST('' '' AS NVARCHAR(MAX)) AS valorDefecto, CAST(1 AS BIT) AS estaActivo, GETDATE() AS fechaCreacion, GETDATE() AS fechaModificacion');
END
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
    FROM dbo.uv_parametro
    WHERE grupo = TRIM(@p_grupo) 
      AND clave = TRIM(@p_clave);

    RETURN ISNULL(@valor, ISNULL(@valorDefecto, ''));
END;
GO
