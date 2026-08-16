USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_parametro]
AS
SELECT 
    [id],
    [grupo],
    [clave],
    [valor],
    [tipoDato],
    [valorDefecto],
    [estaActivo],
    [fechaCreacion],
    [fechaModificacion]
FROM [dbo].[CatalogoParametro]
WHERE [estaActivo] = 1;
GO
