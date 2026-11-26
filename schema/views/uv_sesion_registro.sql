USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 11 (2026-11-26): vista delgada de lectura sobre dbo.Sesion (uv_sesion une uv_grupo y no expone procedenciaTemporal;
-- los SP que solo necesitan la fila leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_sesion_registro]
AS
SELECT		id,
			nombre,
			numero,
			codigo,
			numeroSemana,
			idGrupo = grupo,
			fechaHoraInicio,
			fechaHoraFin,
			procedenciaTemporal
FROM		dbo.Sesion
GO
