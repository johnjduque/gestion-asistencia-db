USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.EstudiantePrograma (uv_estudiante_programa une
-- uv_estudiante_identidad y uv_programa). Sin filtros ni calculos.
CREATE OR ALTER VIEW [dbo].[uv_estudiante_programa_registro]
AS
SELECT		id,
			idEstudiante = estudiante,
			idPrograma = programa
FROM		dbo.EstudiantePrograma
GO
