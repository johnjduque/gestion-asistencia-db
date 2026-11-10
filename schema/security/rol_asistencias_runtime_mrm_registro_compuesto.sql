USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (5): permisos del registro compuesto. EXECUTE sobre los dos SP publicos nuevos (los nucleos usp_*_interno no se conceden).
-- Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_crear_decano_con_facultad', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_crear_decano_con_facultad] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_crear_coordinador_con_programa] TO [rol_asistencias_runtime];
GO
