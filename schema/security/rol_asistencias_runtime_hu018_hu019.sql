USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU018 / HU019: permisos de las consultas del estudiante (plan de estudios por semestres y horas programadas de sus
-- materias). EXECUTE sobre los dos SP publicos nuevos. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plan_estudio_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_horas_programadas_estudiante] TO [rol_asistencias_runtime];
GO
