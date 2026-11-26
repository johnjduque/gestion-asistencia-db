USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 13 (2026-11-26): vista delgada de lectura sobre dbo.Horario (uv_horario une grupo y dia;
-- los SP que solo necesitan la fila leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_horario_registro]
AS
SELECT		id,
			idGrupo = grupo,
			idDia = dia,
			horaInicio,
			horaFin
FROM		dbo.Horario
GO
