USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.SincronizacionParametroExterno (INT-004; la tabla no tenia
-- vista). No expone valorAnterior ni valorNuevo. La deteccion de evento duplicado sigue leyendo la tabla con UPDLOCK, HOLDLOCK.
CREATE OR ALTER VIEW [dbo].[uv_sincronizacion_parametro_externo_registro]
AS
SELECT		id,
			idEvento,
			idParametro = parametro,
			grupo,
			clave,
			operacion,
			resultado,
			ocurridoEnUtc,
			idCorrelacion,
			fechaRegistroUtc
FROM		dbo.SincronizacionParametroExterno
GO
