USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_semestre_plan_estudio]
AS
SELECT		id = sp.id,
			idPlanEstudio = pe.id,
			inp = pe.inp,

			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idSemestre = s.id,
			numeroSemestre = s.numero

FROM		SemestrePlanEstudio sp
INNER JOIN	uv_semestre s
ON			sp.semestre = s.id
INNER JOIN	uv_plan_estudio pe
ON			sp.planEstudio = pe.id
INNER JOIN	uv_programa pr
ON			pe.Idprograma = pr.id
GO
