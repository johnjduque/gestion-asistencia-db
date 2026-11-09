USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: permisos de las sesiones manuales. EXECUTE sobre los SP publicos nuevos y SELECT sobre las vistas nuevas
-- (los nucleos usp_*_interno no se conceden). Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_sesion_manual] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cancelar_sesion_coordinador] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_motivos_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_manual] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_motivo_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
