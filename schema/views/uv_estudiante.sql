USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER     VIEW	[dbo].[uv_estudiante]
AS
SELECT		ei.id,
			ei.idUsuario,
			ei.numeroIdentificacion,
			ei.nombreCompleto,
			ei.estaActivoUsuario,

			-- Informaci?n de la Instituci?n
			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			-- Informaci?n de la Facultad y Programa
			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			-- Trazabilidad
			idPlanEstudio = pe.id,
			inpPlanEstudio = pe.inp,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			-- Perfil del Estudiante (Asumiendo c?digo 'ES')
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			-- Estado L?gico
			estaActivoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO')

FROM		uv_estudiante_identidad ei
INNER JOIN	uv_estudiante_grupo eg 
ON			ei.id = eg.idEstudiante
INNER JOIN	uv_grupo g            
ON			eg.idGrupo = g.id
INNER JOIN	uv_asignatura a       
ON			g.idAsignatura = a.id
INNER JOIN	uv_semestre_plan_estudio spe 
ON			a.idSemestrePlanEstudio = spe.id
INNER JOIN	uv_plan_estudio pe     
ON			spe.idPlanEstudio = pe.id
INNER JOIN	uv_programa pr     
ON			pe.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'ES') p
GO
