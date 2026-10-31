USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTIF-002A: permisos de ejecucion para plantillas de notificacion y resolucion de contacto.
-- Otorga permisos estrictamente sobre los procedimientos publicos al rol de runtime.
-- Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_plantilla_notificacion_activa', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plantilla_notificacion_activa] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_consultar_contacto_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_contacto_notificacion] TO [rol_asistencias_runtime];
GO
