USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: permisos de ejecucion del correo institucional y la verificacion del correo.
-- Solo EXECUTE sobre los SP publicos; sin DML directo sobre dbo.TokenVerificacionCorreo. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_emitir_token_verificacion_correo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_emitir_token_verificacion_correo] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_consultar_token_verificacion_correo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_token_verificacion_correo] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_confirmar_verificacion_correo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_confirmar_verificacion_correo] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_consultar_reenvio_verificacion_correo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_reenvio_verificacion_correo] TO [rol_asistencias_runtime];
GO
