USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-002: permiso de ejecucion del reenvio del enlace de activacion. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_reenvio_activacion_cuenta', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_reenvio_activacion_cuenta] TO [rol_asistencias_runtime];
GO
