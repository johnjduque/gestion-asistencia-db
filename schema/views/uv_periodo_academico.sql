USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_periodo_academico]
AS
SELECT		id = pa.id,
			idInstitucion = i.id,
			nombreInstitucion = i.nombre,
			nombre = pa.nombre,
			codigo = pa.codigo,
			fechaInicio = pa.fechaInicio,
			fechaFin = pa.fechaFin,
			anio = pa.anio

FROM		PeriodoAcademico pa
INNER JOIN	uv_institucion i
ON			pa.institucion = i.id
GO
