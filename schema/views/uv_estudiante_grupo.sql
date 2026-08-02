USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_estudiante_grupo]
AS
SELECT		id = eg.id,
			idEstadoEstudiante = eeg.id,
			nombreEstadoEstudiante = eeg.nombre,
			codigoEstadoEstudiante = eeg.codigo,
			idEstudiante = e.id,
			nombreCompletoEstudiante = e.nombreCompleto,
			idGrupo = g.id,
			codigoGrupo = g.codigo,
			nombreGrupo = g.nombre

FROM		EstudianteGrupo eg
INNER JOIN	uv_estudiante_identidad e
ON			eg.estudiante = e.id
INNER JOIN	uv_estado_estudiante_grupo eeg
ON			eg.estado = eeg.id
INNER JOIN	uv_grupo g
ON			eg.grupo = g.id
GO
