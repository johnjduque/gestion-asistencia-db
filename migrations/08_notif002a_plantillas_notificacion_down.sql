USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN: NOTIF-002A - Revertir plantillas de notificacion y contacto
-- ============================================================================

IF OBJECT_ID('dbo.usp_consultar_plantilla_notificacion_activa', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_consultar_plantilla_notificacion_activa;
END
GO

IF OBJECT_ID('dbo.usp_consultar_plantilla_notificacion_activa_interno', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_consultar_plantilla_notificacion_activa_interno;
END
GO

IF OBJECT_ID('dbo.usp_consultar_contacto_notificacion', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_consultar_contacto_notificacion;
END
GO

IF OBJECT_ID('dbo.usp_consultar_contacto_notificacion_interno', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_consultar_contacto_notificacion_interno;
END
GO

IF OBJECT_ID('dbo.PlantillaNotificacionMarcador', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.PlantillaNotificacionMarcador;
END
GO

IF OBJECT_ID('dbo.PlantillaNotificacion', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.PlantillaNotificacion;
END
GO
