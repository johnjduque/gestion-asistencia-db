USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 3 (2026-11-25): lectura de las emisiones de tokens de verificacion de correo para que los SP no lean la
-- tabla base (usp_consultar_reenvio_activacion_cuenta calcula la espera minima entre envios con la ultima emision).
-- Expone solo el usuario y la fecha de emision: nunca el hash del token ni sus fechas de uso o revocacion.
-- Reversion: DROP VIEW [dbo].[uv_token_verificacion_correo] (ver docs/work-items/SKILLS-BD-LOTE-3/PLAN.md).
CREATE OR ALTER VIEW [dbo].[uv_token_verificacion_correo]
AS
SELECT		t.id,
			idUsuario = t.usuario,
			t.fechaEmisionUtc
FROM		TokenVerificacionCorreo t
GO
