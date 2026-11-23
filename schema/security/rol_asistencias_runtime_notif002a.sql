USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTIF-002A: permisos de ejecucion para la resolucion de contacto de notificaciones.
-- Otorga permisos estrictamente sobre los procedimientos publicos al rol de runtime. Los permisos sobre la lectura de plantillas se
-- retiraron con la migracion 71 (las plantillas viven en el Servicio de Notificaciones).
-- Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_contacto_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_contacto_notificacion] TO [rol_asistencias_runtime];
GO
