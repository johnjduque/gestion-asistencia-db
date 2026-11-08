USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): permisos para validacion de carga masiva.
-- ============================================================================
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_validar_carga_masiva_usuarios] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_jerarquia_alta_usuario] TO [rol_asistencias_runtime];
GO
