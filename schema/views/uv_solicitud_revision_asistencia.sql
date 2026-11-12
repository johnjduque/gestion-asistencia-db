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
			totalSoportes = (SELECT COUNT(*) FROM uv_soporte_reclamo sop WHERE sop.idSolicitud = sr.id),
			-- PC (puntos de control, reclamo por toma; columnas al final): toma reclamada (NULL = reclamo de la sesion) y resultado
			-- de la aprobacion (AN = estuvo presente, EX = ausencia justificada; NULL si no se aprobo o se aprobo antes de PC)
			idToma = sr.toma,
			numeroToma = tom.numero,
			codigoResultadoAprobacion = rcr.codigo

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
LEFT JOIN	CategoriaJustificacion cat
ON			sr.categoriaJustificacion = cat.id
LEFT JOIN	TomaAsistencia tom
ON			sr.toma = tom.id
LEFT JOIN	RazonCausa rcr
ON			sr.razonCausaResolucion = rcr.id
GO
