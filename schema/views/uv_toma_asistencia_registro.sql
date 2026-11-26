USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.TomaAsistencia (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_toma_asistencia_registro]
AS
SELECT		id,
			idSesion = sesion,
			numero,
			idModo = modo,
			idEstado = estado,
			esImplicita,
			idDocenteApertura = docenteApertura,
			fechaAperturaUtc,
			fechaCierreUtc,
			totalAusentesMarcados,
			idCorrelacionApertura,
			idCorrelacionCierre
FROM		dbo.TomaAsistencia
GO
