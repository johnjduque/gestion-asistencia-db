USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 11 (2026-11-26): vista delgada de lectura sobre dbo.SolicitudRevisionAsistencia (uv_solicitud_revision_asistencia une
-- asistencia, estado, categoria, toma y soportes; los SP que solo necesitan las llaves leen por esta vista; las lecturas con bloqueo y
-- las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_solicitud_revision_asistencia_registro]
AS
SELECT		id,
			nombre,
			idAsistencia = asistencia,
			fecha,
			idEstado = estado,
			justificacionSolicitud,
			justificacionRespuesta,
			idCategoriaJustificacion = categoriaJustificacion,
			idToma = toma,
			idRazonCausaResolucion = razonCausaResolucion
FROM		dbo.SolicitudRevisionAsistencia
GO
