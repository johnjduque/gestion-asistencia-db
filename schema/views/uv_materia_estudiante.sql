USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W2B: una fila por matricula (EstudianteGrupo) del estudiante con su asignatura, grupo y creditos. Es la unica fuente
-- de las materias del estudiante: usp_consultar_materias_estudiante (listado) y usp_consultar_resumen_materias_estudiante
-- (indicadores del tablero) la leen y aplican el mismo estado de matricula (MATRICULA/ESTADO_INSCRITA), de modo que el
-- listado y el resumen no pueden discrepar. No filtra por periodo ni por estado: ese criterio lo aplica cada SP.
CREATE OR ALTER VIEW [dbo].[uv_materia_estudiante]
AS
SELECT		idEstudianteGrupo = eg.id,
			idEstudiante = e.id,
			idUsuario = e.usuario,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,
			creditos = a.credito,
			codigoEstadoEstudiante = eg.codigoEstadoEstudiante

FROM		dbo.Estudiante e
INNER JOIN	dbo.uv_estudiante_grupo eg
ON			eg.idEstudiante = e.id
INNER JOIN	dbo.uv_grupo g
ON			g.id = eg.idGrupo
INNER JOIN	dbo.uv_asignatura a
ON			a.id = g.idAsignatura
GO
