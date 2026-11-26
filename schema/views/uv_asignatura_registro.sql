USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.Asignatura (uv_asignatura une area y componente y cuenta los
-- planes; los SP que solo necesitan la fila leen por esta vista; las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_asignatura_registro]
AS
SELECT		id,
			codigo,
			nombre,
			credito,
			idArea = area,
			idComponente = componente,
			estado,
			horasSemanales
FROM		dbo.Asignatura
GO
