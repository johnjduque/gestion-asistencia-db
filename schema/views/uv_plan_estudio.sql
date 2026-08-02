USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_plan_estudio]
AS
SELECT		pe.id,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,
			inp = pe.inp,
			estaActivoPlanEstudio = IIF(pr.estaActivoPrograma = 0, 0, 1),
			estaActivoTextoPlanEstudio = IIF(pr.estaActivoPrograma = 0, 'NO', 'SI'),
			justificacionEstado =	CASE
										WHEN pr.estaActivoPrograma = 0 THEN 'Plan Estudio inactivo porque programa est? inactivo.'
										ELSE 'Plan Estudio activo.'
									END

FROM		PlanEstudio pe
INNER JOIN	uv_programa pr
ON			pe.programa = pr.id
GO
