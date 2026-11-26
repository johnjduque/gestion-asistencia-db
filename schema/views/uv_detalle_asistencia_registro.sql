USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 11 (2026-11-26): vista delgada de lectura sobre dbo.DetalleAsistencia (uv_detalle_asistencia_v2 exige toma y calcula
-- horas; los SP que solo necesitan la fila leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_detalle_asistencia_registro]
AS
SELECT		id,
			codigo,
			idAsistencia = asistencia,
			asistio,
			idRazonCausa = razonCausa,
			fechaHoraInicio,
			fechaHoraFin,
			idToma = toma,
			registradoPorEstudiante,
			fechaRegistroUtc
FROM		dbo.DetalleAsistencia
GO
