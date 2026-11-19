USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D6/D7: permisos del rol runtime sobre las solicitudes de sesion del docente y el calendario de sesiones. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_docente_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_sesion_docente_paginado] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_calendario_estudiante] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_docente', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_calendario_docente] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.uv_sesion_calendario', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_calendario] TO [rol_asistencias_runtime];
GO
