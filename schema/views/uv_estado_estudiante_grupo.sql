USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_estado_estudiante_grupo]
AS
SELECT  id,
		nombre,
		codigo
FROM	EstadoEstudianteGrupo
GO
