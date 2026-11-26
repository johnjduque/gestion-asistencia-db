USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.PeriodoRecesoAcademico (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_receso_academico_registro]
AS
SELECT		id,
			idPeriodoAcademico = periodoAcademico,
			fecha,
			motivo,
			estaActivo,
			fechaCreacionUtc,
			idUsuarioCreador = usuarioCreador,
			idCorrelacion
FROM		dbo.PeriodoRecesoAcademico
GO
