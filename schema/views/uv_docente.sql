USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM: programa y plan desde uv_grupo_programa. Grano 1 por (docente, grupo, programa del grupo).
CREATE OR ALTER    VIEW	[dbo].[uv_docente]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,

			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idPlanEstudio = gp.idPlanEstudio,
			inpPlanEstudio = gp.inpPlanEstudio,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO')

FROM		uv_docente_identidad di
INNER JOIN	uv_grupo g
ON			di.id = g.idDocente
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DO') p
GO
