USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2): permisos de varios soportes por reclamo (HU014/HU015). EXECUTE sobre el comando v3 y la consulta de
-- configuracion; SELECT sobre uv_soporte_reclamo. El nucleo usp_internal_radicar_solicitud_revision NO se concede (lo invocan v2 y v3).
-- usp_radicar_solicitud_revision_asistencia_v2 conserva el GRANT de rol_asistencias_runtime_lb004d.sql. Aditivo e idempotente: el bucle
-- uv_* de rol_asistencias_runtime.sql ya cubre la vista cuando deploy_schema.ps1 aplica la seguridad despues de las vistas; el GRANT
-- explicito cubre los objetos creados por la migracion 21 fuera de ese despliegue.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_radicar_solicitud_revision_asistencia_v3] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_configuracion_reclamos] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_soporte_reclamo] TO [rol_asistencias_runtime];
GO
