USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 13 (2026-11-26): vista delgada de lectura sobre dbo.SesionProcedenciaClasificacion (no habia vista de la tabla;
-- los SP que solo necesitan la fila leen por esta vista; las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_sesion_procedencia_clasificacion_registro]
AS
SELECT		id,
			idSesion = sesion,
			ambiente,
			idManifiesto,
			hashEvidencia,
			procedenciaAnterior,
			procedenciaNueva,
			fechaHoraInicioAnterior,
			fechaHoraFinAnterior,
			fechaHoraInicioUtc,
			fechaHoraFinUtc,
			idUsuarioEjecutor = usuarioEjecutor,
			idUsuarioAprobador = usuarioAprobador,
			idCorrelacion,
			fechaRegistro
FROM		dbo.SesionProcedenciaClasificacion
GO
