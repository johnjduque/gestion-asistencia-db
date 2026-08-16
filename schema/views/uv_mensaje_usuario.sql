USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_mensaje_usuario]
AS
SELECT 
    [id],
    [codigo],
    [tipoMensaje],
    [severidad],
    [contenido],
    [estaActivo],
    [fechaCreacion],
    [fechaModificacion]
FROM [dbo].[CatalogoMensajeUsuario]
WHERE [estaActivo] = 1;
GO
