USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 11 (2026-11-26): vista delgada de lectura sobre dbo.ArchivoSoporte (uv_soporte_reclamo filtra los adjuntos y no expone
-- todas las columnas; los SP leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_archivo_soporte_registro]
AS
SELECT		id,
			idUsuarioPropietario = usuarioPropietario,
			idSolicitudRevisionAsistencia = solicitudRevisionAsistencia,
			nombreOriginal,
			tipoContenido,
			tamanioBytes,
			checksumSha256,
			estado,
			fechaRegistroUtc,
			fechaAdjuncionUtc,
			fechaCambioEstadoUtc,
			idCorrelacionRegistro,
			idCorrelacionAdjuncion
FROM		dbo.ArchivoSoporte
GO
