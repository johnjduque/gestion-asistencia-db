USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 12 (2026-11-26): vista delgada de lectura sobre dbo.AvisoSesionSinToma (NOTOMA-001; la tabla no tenia vista). El
-- registro del aviso sigue leyendo la tabla con UPDLOCK, HOLDLOCK antes del INSERT.
CREATE OR ALTER VIEW [dbo].[uv_aviso_sesion_sin_toma]
AS
SELECT		idSesion = sesion,
			fechaAvisoUtc,
			totalCoordinadoresAvisados,
			idCorrelacion
FROM		dbo.AvisoSesionSinToma
GO
