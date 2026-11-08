USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.9-a (CONTRACT D §11.2): permisos de los hallazgos medios. Solo EXECUTE sobre los SP publicos nuevos; los nucleos
-- usp_*_interno que usan NO se conceden. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_grupo_facultad_detalle', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_grupo_facultad_detalle] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_periodos_academicos_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_periodos_academicos_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_validar_acceso_reporte_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_validar_acceso_reporte_grupo] TO [rol_asistencias_runtime];
GO
