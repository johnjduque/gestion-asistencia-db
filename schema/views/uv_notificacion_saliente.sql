USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 8 (2026-11-26): vista delgada de lectura sobre dbo.NotificacionSaliente (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_notificacion_saliente]
AS
SELECT		id,
			tipo,
			asunto,
			mensaje,
			destinatarios,
			datos,
			idEstado,
			intentos,
			creadoEn,
			proximoIntentoEn,
			reservadoHasta,
			reservadoPor,
			entregadoEn,
			codigoError,
			detalleError,
			idCorrelacion,
			traceId,
			spanId
FROM		dbo.NotificacionSaliente
GO
