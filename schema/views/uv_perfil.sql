USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_perfil]
AS
SELECT	id,
		codigo,
		nombre,
		nivel_acceso
FROM	Perfil
GO
