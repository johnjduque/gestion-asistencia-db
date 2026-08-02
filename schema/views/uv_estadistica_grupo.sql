USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_estadistica_grupo]
AS
SELECT			g.id,
				cupoMaximoConfigurado = g.cantidadEstudiantes,
				totalMatriculadosGrupo = ISNULL(eg.totalMatriculados, 0),
				cantidadCanceladoPorVoluntadPropia = ISNULL(cvp.canceladaPorVoluntadPropia, 0),
				cantidadActivos = ISNULL(a.activo, 0),
				cantidadCanceladoPorInasistencia = ISNULL(ci.canceladoInasistenticia, 0),
				cantidadFinalizados = ISNULL(f.finalizado, 0)
FROM			Grupo g
LEFT OUTER JOIN	(
					SELECT		eg.grupo, totalMatriculados = COUNT(1)
					FROM		EstudianteGrupo eg
					GROUP BY	eg.grupo
				) eg
ON				g.id = eg.grupo
LEFT OUTER JOIN	(
					SELECT		eg.grupo, canceladaPorVoluntadPropia = COUNT(1)
					FROM		EstudianteGrupo eg
					INNER JOIN	EstadoEstudianteGrupo e
					ON			eg.estado = e.id
					WHERE		e.codigo = 'CVP'
					GROUP BY	eg.grupo
				) cvp
ON				g.id = cvp.grupo
LEFT OUTER JOIN	(
					SELECT		eg.grupo, activo = COUNT(1)
					FROM		EstudianteGrupo eg
					INNER JOIN	EstadoEstudianteGrupo e
					ON			eg.estado = e.id
					WHERE		e.codigo = 'A'
					GROUP BY	eg.grupo
				) a
ON				g.id = a.grupo
LEFT OUTER JOIN	(
					SELECT		eg.grupo, canceladoInasistenticia = COUNT(1)
					FROM		EstudianteGrupo eg
					INNER JOIN	EstadoEstudianteGrupo e
					ON			eg.estado = e.id
					WHERE		e.codigo = 'CI'
					GROUP BY	eg.grupo
				) ci
ON				g.id = ci.grupo
LEFT OUTER JOIN	(
					SELECT		eg.grupo, finalizado = COUNT(1)
					FROM		EstudianteGrupo eg
					INNER JOIN	EstadoEstudianteGrupo e
					ON			eg.estado = e.id
					WHERE		e.codigo = 'F'
					GROUP BY	eg.grupo
				) f
ON				g.id = f.grupo
GO
