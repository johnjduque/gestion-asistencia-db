USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W3M: permiso del runtime para la matriz de asistencia del grupo y el resumen de sesiones del docente. Los SP validan
-- el perfil DOCENTE y la titularidad del grupo antes de leer filas. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado', N'P') IS NULL
    THROW 52321, 'W3M_RUNTIME_GRANT: usp_consultar_matriz_asistencia_grupo_docente_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_resumen_sesiones_grupo_docente', N'P') IS NULL
    THROW 52322, 'W3M_RUNTIME_GRANT: usp_consultar_resumen_sesiones_grupo_docente requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_matriz_asistencia_grupo_docente_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_resumen_sesiones_grupo_docente] TO [rol_asistencias_runtime];
GO
