USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_tipo_identificacion]
AS
SELECT  id,
		tipoIdentificacion,
		nombre
FROM	TipoIdentificacion
GO
