USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_asistencia]
AS
SELECT		id = asi.id,
			idEstudianteGrupo = eg.id,
			idSesion = se.id

FROM		Asistencia asi
INNER JOIN	uv_estudiante_grupo eg
ON			asi.estudianteGrupo = eg.id
INNER JOIN	uv_sesion se 
ON			asi.sesion = se.id
WHERE		eg.idGrupo = se.idGrupo
GO
