USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_semestre]
AS
SELECT  id,
		nombre,
		numero,
		codigo
FROM	Semestre
GO
