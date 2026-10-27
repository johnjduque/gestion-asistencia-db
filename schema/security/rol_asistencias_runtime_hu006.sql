USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU006: permiso del runtime para la consulta del perfil propio. El SP solo lee el usuario ejecutor.
-- Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_perfil_usuario', N'P') IS NULL
    THROW 52192, 'HU006_RUNTIME_GRANT: usp_consultar_perfil_usuario requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_perfil_usuario] TO [rol_asistencias_runtime];
GO
