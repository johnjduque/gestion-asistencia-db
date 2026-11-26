USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.CatalogoParametroEdicion (uv_parametro_edicion une parametro,
-- grupo protegido y ultimo cambio; los SP que solo necesitan la fila leen por esta vista; las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_parametro_edicion_registro]
AS
SELECT		idParametro = parametro,
			esEditable,
			valorMinimo,
			valorMaximo,
			valoresPermitidos,
			idParametroDebeSerMenorQue = parametroDebeSerMenorQue,
			etiqueta,
			descripcion,
			unidad,
			categoriaVisual,
			orden,
			formato
FROM		dbo.CatalogoParametroEdicion
GO
