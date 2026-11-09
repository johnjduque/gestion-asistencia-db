USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (DEC-019): catalogo de asignaturas, 1 fila por asignatura. La pertenencia a planes vive en
-- uv_asignatura_plan_estudio (tabla puente AsignaturaPlanEstudio).
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
			estaActivaAsignatura = a.estado,
			estaActivaTextoAsignatura = IIF(a.estado = 1, 'SI', 'NO'),
			totalPlanesActivos = (SELECT COUNT(*) FROM AsignaturaPlanEstudio x WHERE x.asignatura = a.id AND x.estaActivo = 1)

FROM		Asignatura a
INNER JOIN	uv_area ar
ON			a.area = ar.id
INNER JOIN	uv_componente co
ON			a.componente = co.id
GO
