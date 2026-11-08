USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (DEC-020, R6): 1 fila por (estudiante, grupo, programa del grupo); ya no exige EstudiantePrograma.
-- tieneVinculoPrograma = 1 cuando el estudiante tiene EstudiantePrograma en ese programa.
CREATE OR ALTER     VIEW	[dbo].[uv_estudiante]
AS
SELECT		ei.id,
			ei.idUsuario,
			ei.numeroIdentificacion,
			ei.nombreCompleto,
			ei.estaActivoUsuario,

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

			estaActivoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO'),
			tieneVinculoPrograma = CAST(IIF(EXISTS (SELECT 1 FROM EstudiantePrograma ep WHERE ep.estudiante = ei.id AND ep.programa = pr.id), 1, 0) AS BIT)

FROM		uv_estudiante_identidad ei
INNER JOIN	uv_estudiante_grupo eg
ON			ei.id = eg.idEstudiante
INNER JOIN	uv_grupo g
ON			eg.idGrupo = g.id
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'ES') p
GO
