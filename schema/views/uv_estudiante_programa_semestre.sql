USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 7 (2026-11-26): vinculo estudiante-programa con el semestre actual (EstudiantePrograma.semestreActual, migracion 63),
-- para que los SP no lean la tabla base. uv_estudiante_programa no trae el semestre y no se cambia su forma. Sin uniones: una fila
-- por vinculo. Reversion: DROP VIEW [dbo].[uv_estudiante_programa_semestre] (ver docs/work-items/SKILLS-BD-LOTE-7/PLAN.md).
CREATE OR ALTER VIEW [dbo].[uv_estudiante_programa_semestre]
AS
SELECT		ep.id,
			idEstudiante = ep.estudiante,
			idPrograma = ep.programa,
			semestreActual = ep.semestreActual
FROM		EstudiantePrograma ep
GO
