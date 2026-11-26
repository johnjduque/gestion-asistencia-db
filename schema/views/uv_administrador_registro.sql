USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.Administrador (uv_administrador une usuario, institucion y
-- perfil; los SP que solo necesitan la fila leen por esta vista; las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_administrador_registro]
AS
SELECT		id,
			idUsuario = usuario,
			idInstitucion = institucion
FROM		dbo.Administrador
GO
