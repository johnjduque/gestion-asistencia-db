USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_asignatura]
AS
SELECT		id = a.id,
			codigo = a.codigo,
			nombre = a.nombre,
			credito = a.credito,
			idArea = ar.id,
			nombreArea = ar.nombre,
			idComponente = co.id,
			nombreComponente = co.nombre,
			idSemestrePlanEstudio = a.semestrePlanEstudio,
			inp = pe.inp,
			nombrePrograma = pr.nombrePrograma,
			codigoSemestre = s.codigo,
			estaActivaAsignatura = a.estado,
			estaActivaTextoAsignatura = IIF(a.estado = 1, 'SI', 'NO')

FROM		Asignatura a
INNER JOIN	uv_area ar
ON			a.area = ar.id
INNER JOIN	uv_componente co
ON			a.componente = co.id
INNER JOIN	uv_semestre_plan_estudio sp
ON			a.SemestrePlanEstudio = sp.id
INNER JOIN	uv_semestre s
ON			sp.idsemestre = s.id
INNER JOIN	uv_plan_estudio pe
ON			sp.idPlanEstudio = pe.id
INNER JOIN	uv_programa pr
ON			pe.Idprograma = pr.id
GO
