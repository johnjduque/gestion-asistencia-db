USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 8 (2026-11-26): vista delgada de lectura sobre dbo.EstadoNotificacion (los SP leen por vista; las lecturas
-- con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_estado_notificacion]
AS
SELECT		id,
			codigo,
			nombre,
			esTerminal
FROM		dbo.EstadoNotificacion
GO
