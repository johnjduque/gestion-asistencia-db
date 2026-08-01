USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_grupo]
AS
SELECT		id = g.id,
			idPeriodoAcademico = pa.id,
			fechaInicioPeriodoAcademico = pa.fechaInicio,
			fechaFinPeriodoAcademico = pa.fechaFin,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			
			-- Referencia al Docente
			idDocente = g.docente, 
			
			codigo = g.codigo,
			nombre = g.nombre,
			
			-- CAPACIDAD Y ESTAD?STICAS
			capacidadMaximaPermitida = g.cantidadEstudiantes, 
			estudiantesActivos = eg.cantidadActivos,
			estudiantesFinalizados = eg.cantidadFinalizados,
			estudiantesCanceladosVoluntad = eg.cantidadCanceladoPorVoluntadPropia,
			estudiantesCanceladosInasistencia = eg.cantidadCanceladoPorInasistencia,
			
			-- C?LCULO DE DISPONIBILIDAD
			cuposDisponibles = (g.cantidadEstudiantes - eg.cantidadActivos),
			
			-- ESTADO DE HABILITACI?N
			grupoEstaHablitado = IIF(GETDATE() BETWEEN pa.fechaInicio AND pa.fechaFin, 1, 0),
			grupoEstaHablitadoTexto = IIF(GETDATE() BETWEEN pa.fechaInicio AND pa.fechaFin, 'SI', 'NO')

FROM		Grupo g
INNER JOIN	uv_periodo_academico pa 
ON			g.periodoAcademico = pa.id
INNER JOIN	uv_asignatura a 
ON			g.asignatura = a.id
INNER JOIN	uv_estadistica_grupo eg 
ON			g.id = eg.id
GO
