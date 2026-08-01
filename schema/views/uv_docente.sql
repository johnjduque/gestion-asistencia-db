USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_docente]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,

			-- Informaci?n Institucional
			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			-- Jerarqu?a Acad?mica
			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			-- Detalle de la Asignatura/Grupo
			idPlanEstudio = pe.id,
			inpPlanEstudio = pe.inp,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			-- Informaci?n del Perfil
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			-- Estado L?gico (Docente activo + Programa activo)
			estaActivoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO')

FROM		uv_docente_identidad di
INNER JOIN	uv_grupo g            
ON			di.id = g.idDocente
INNER JOIN	uv_asignatura a       
ON			g.idAsignatura = a.id
INNER JOIN	uv_semestre_plan_estudio spe 
ON			a.idSemestrePlanEstudio = spe.id
INNER JOIN	uv_plan_estudio pe     
ON			spe.idPlanEstudio = pe.id
INNER JOIN	uv_programa pr     
ON			pe.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DO') p
GO
