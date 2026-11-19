USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1): permiso del rol runtime sobre las faltas reclamables del estudiante. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_faltas_reclamables_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_faltas_reclamables_estudiante] TO [rol_asistencias_runtime];
GO
