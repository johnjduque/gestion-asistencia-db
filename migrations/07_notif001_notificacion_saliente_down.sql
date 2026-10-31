USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN: NOTIF-001 - Revertir capacidad de notificaciones outbox
-- ============================================================================

IF OBJECT_ID('dbo.NotificacionSaliente', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.NotificacionSaliente;
END
GO

IF OBJECT_ID('dbo.EstadoNotificacion', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.EstadoNotificacion;
END
GO
