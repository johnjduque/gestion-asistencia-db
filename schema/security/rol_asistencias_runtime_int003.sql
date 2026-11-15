USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INT-003: el backend sincroniza en dbo.CatalogoMensajeUsuario los textos que cambian en MessageUcoLab. Solo EXECUTE sobre
-- el SP publico usp_sincronizar_mensaje_usuario; sin DML directo sobre la tabla. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_sincronizar_mensaje_usuario', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_sincronizar_mensaje_usuario] TO [rol_asistencias_runtime];
GO
