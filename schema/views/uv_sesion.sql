USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_sesion]
AS
SELECT		id = se.id,
			nombre = se.nombre,
			numero = se.numero,
			codigo = se.codigo,
			numeroSemana = se.numeroSemana,
			idGrupo = g.id,
			codigoGrupo = g.codigo,
			nombreGrupo = g.nombre,
			fechaHoraInicio = se.fechaHoraInicio,
			fechaHoraFin = se.fechaHoraFin,
			descripcion = se.descripcion,
			aula = se.aula,
			tipo = se.tipo

FROM		Sesion se
INNER JOIN	uv_grupo g
ON			se.grupo = g.id
GO
