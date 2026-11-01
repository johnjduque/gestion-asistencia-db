USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F1 (2026-10-30): permiso de minimo privilegio del SP publico que guarda el horario semanal del grupo.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). La escritura sobre dbo.Horario solo pasa
-- por usp_guardar_horarios_grupo; el runtime no la escribe directo.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_guardar_horarios_grupo', N'P') IS NULL
    THROW 52193, 'F1_HORARIO_GRUPO_RUNTIME_GRANT: usp_guardar_horarios_grupo requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_guardar_horarios_grupo] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[Horario] TO [rol_asistencias_runtime];
GO
