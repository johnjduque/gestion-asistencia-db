USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Migracion 63: permiso del runtime para registrar el semestre actual de un estudiante en un programa (coordinador).
-- El SP valida RBAC y titularidad del programa. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_actualizar_semestre_estudiante_programa', N'P') IS NULL
    THROW 52199, 'SEMESTRE_ESTUDIANTE_RUNTIME_GRANT: usp_actualizar_semestre_estudiante_programa requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_actualizar_semestre_estudiante_programa] TO [rol_asistencias_runtime];
GO
