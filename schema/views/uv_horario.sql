USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_horario]
AS
SELECT		id = h.id,
			idGrupo = g.id,
			idPeriodoAcademico = g.idPeriodoAcademico,
			codigoGrupo = g.codigo,
			nombreGrupo = g.nombre,
			idDia = di.id,
			nombreDia = di.nombre,
			horaInicio = h.horaInicio,
			horaFin = h.horaFin

FROM		Horario h
INNER JOIN	uv_grupo g
ON			h.grupo = g.id
INNER JOIN	uv_dia di
ON			h.dia = di.id
GO
