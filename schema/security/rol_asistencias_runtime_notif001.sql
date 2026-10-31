USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTIF-001: permisos de ejecucion para la capacidad de notificaciones outbox.
-- Otorga permisos estrictamente sobre los procedimientos publicos al rol de runtime.
-- Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_registrar_notificacion_saliente', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_notificacion_saliente] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_reservar_notificaciones_salientes', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_reservar_notificaciones_salientes] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_marcar_notificacion_entregada', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_marcar_notificacion_entregada] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_registrar_fallo_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_fallo_notificacion] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_depurar_notificaciones_salientes', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_depurar_notificaciones_salientes] TO [rol_asistencias_runtime];
GO
