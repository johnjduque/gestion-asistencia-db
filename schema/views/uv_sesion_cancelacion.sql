USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.SesionCancelacion (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_sesion_cancelacion]
AS
SELECT		idSesion = sesion,
			idTipoCancelacion = tipoCancelacion,
			motivo,
			idDiaFestivo = diaFestivo,
			idRecesoAcademico = recesoAcademico,
			idUsuarioEjecutor = usuarioEjecutor,
			fechaCancelacionUtc,
			idCorrelacion
FROM		dbo.SesionCancelacion
GO
