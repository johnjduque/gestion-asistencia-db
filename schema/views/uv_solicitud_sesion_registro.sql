USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 13 (2026-11-26): vista delgada de lectura sobre dbo.SesionSolicitud (uv_solicitud_sesion une sesion, grupo, programa y estado;
-- los SP que solo necesitan la fila leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_solicitud_sesion_registro]
AS
SELECT		idSesion = sesion,
			idEstado,
			idUsuarioSolicitante = usuarioSolicitante,
			fechaSolicitudUtc,
			idUsuarioResolucion = usuarioResolucion,
			fechaResolucionUtc,
			observacion,
			idCorrelacion
FROM		dbo.SesionSolicitud
GO
