USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Migracion 65: categorias de justificacion para la administracion (activas e inactivas, con estaActivo). Solo la lee el
-- ADMINISTRADOR (ruta /api/v1/admin/categorias-justificacion); la oferta al estudiante usa uv_categoria_justificacion (solo activas).
CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion_admin]
AS
SELECT  id,
        codigo,
        nombre,
        descripcion,
        requiereSoporte,
        estaActivo
FROM    dbo.CategoriaJustificacion
GO
