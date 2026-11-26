USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.PeriodoAcademico (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_periodo_academico_fechas]
AS
SELECT		id,
			idInstitucion = institucion,
			nombre,
			codigo,
			fechaInicio,
			fechaFin,
			anio,
			fechaCierreUtc
FROM		dbo.PeriodoAcademico
GO
