USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 10 (2026-11-26): vista delgada de lectura sobre dbo.EvaluacionAlertaGrupo (no tenia vista; los SP leen por vista;
-- las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_evaluacion_alerta_grupo]
AS
SELECT		idGrupo = grupo,
			fechaCorteUtc,
			idCorrelacionUltima,
			totalEvaluaciones
FROM		dbo.EvaluacionAlertaGrupo
GO
