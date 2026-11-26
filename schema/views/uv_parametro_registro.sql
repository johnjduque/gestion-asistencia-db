USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.CatalogoParametro (uv_parametro solo muestra los activos; los SP
-- que leen la fila sin importar su estado leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_parametro_registro]
AS
SELECT		id,
			grupo,
			clave,
			valor,
			tipoDato,
			valorDefecto,
			estaActivo,
			fechaCreacion,
			fechaModificacion
FROM		dbo.CatalogoParametro
GO
