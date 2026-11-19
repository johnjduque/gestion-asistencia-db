USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-GEN-01: permiso de minimo privilegio del SP publico de solo lectura que previsualiza el horario propuesto de un grupo.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). El SP no escribe: solo calcula y devuelve un conjunto de filas.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_previsualizar_horario_grupo', N'P') IS NULL
    THROW 52960, 'SES_GEN_01_RUNTIME_GRANT: usp_previsualizar_horario_grupo requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_previsualizar_horario_grupo] TO [rol_asistencias_runtime];
GO
