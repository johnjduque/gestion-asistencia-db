USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_solicitud_revision_asistencia]
AS
SELECT		id = sr.id,
			nombre = sr.nombre,
			idAsistencia = asi.id,
			fecha = sr.fecha,
			idEstado = est.id,
			nombreEstado = est.nombre,
			justificacionSolicitud = sr.justificacionSolicitud,
			justificacionRespuesta = sr.justificacionRespuesta,
			-- CULM-001 D.2 (TD-060, HU015): categoria persistida y total de soportes vinculados (columnas al final)
			idCategoriaJustificacion = cat.id,
			codigoCategoria = cat.codigo,
			nombreCategoria = cat.nombre,
			totalSoportes = (SELECT COUNT(*) FROM uv_soporte_reclamo sop WHERE sop.idSolicitud = sr.id)

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
LEFT JOIN	CategoriaJustificacion cat
ON			sr.categoriaJustificacion = cat.id
GO
