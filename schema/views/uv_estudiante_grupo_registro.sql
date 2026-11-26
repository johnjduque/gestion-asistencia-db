USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.EstudianteGrupo (uv_estudiante_grupo une identidad y
-- estadisticas; los SP que solo necesitan las llaves leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_estudiante_grupo_registro]
AS
SELECT		id,
			idEstado = estado,
			idEstudiante = estudiante,
			idGrupo = grupo
FROM		dbo.EstudianteGrupo
GO
