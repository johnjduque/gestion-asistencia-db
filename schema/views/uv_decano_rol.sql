USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 4 (2026-11-25): rol de decano con su estado propio (Decano.estado), sin unir el usuario ni la facultad,
-- para que los SP no lean la tabla base. uv_decano combina usuario, rol y facultad en estaActivoDecano y uv_decano_identidad
-- no trae el estado del rol. Reversion: DROP VIEW [dbo].[uv_decano_rol] (ver docs/work-items/SKILLS-BD-LOTE-4/PLAN.md).
CREATE OR ALTER VIEW [dbo].[uv_decano_rol]
AS
SELECT		d.id,
			idUsuario = d.usuario,
			estaActivoRolDecano = d.estado
FROM		Decano d
GO
