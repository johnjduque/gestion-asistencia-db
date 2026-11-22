USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Permisos: rol_asistencias_runtime_notif002b (NOTIF-002B + TD-069)
-- Ambito: destinatarios de reclamos de asistencia. La administracion de plantillas, el monitor de la cola y el reintento manual
--         (NOTIF-002B, TD-069) se retiraron con la migracion 71: viven en el Servicio de Notificaciones.
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

-- 1. Destinatarios de reclamo de asistencia (HU010 / HU037 / HU042)
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_reclamo_asistencia', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_reclamo_asistencia] TO [rol_asistencias_runtime];
GO
