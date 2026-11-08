USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (R6): 1 fila por (matricula, programa del grupo en el que el estudiante tiene EstudiantePrograma).
CREATE OR ALTER VIEW [dbo].[uv_estudiante_grupo_programa]
AS
SELECT  id = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idPrograma = gp.idPrograma
FROM    uv_estudiante_grupo eg
INNER JOIN uv_grupo_programa gp ON gp.idGrupo = eg.idGrupo
INNER JOIN EstudiantePrograma ep ON ep.estudiante = eg.idEstudiante AND ep.programa = gp.idPrograma
GO
