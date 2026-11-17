USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W2B: permiso del runtime para el resumen de materias del estudiante (indicadores del tablero). El SP valida el perfil
-- ESTUDIANTE y solo lee las matriculas del ejecutor. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_resumen_materias_estudiante', N'P') IS NULL
    THROW 52321, 'W2B_RUNTIME_GRANT: usp_consultar_resumen_materias_estudiante requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_resumen_materias_estudiante] TO [rol_asistencias_runtime];
GO
