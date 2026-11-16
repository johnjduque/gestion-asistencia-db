USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W2A (punto 3): permiso del runtime para las opciones de filtro (asignaturas y docentes con grupos en el ambito del
-- usuario) del consolidado de asistencia. Los SP validan el perfil y limitan las filas con uv_auth_grupo.
-- Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_asignaturas_ambito_consolidado', N'P') IS NULL
    THROW 52311, 'W2A_RUNTIME_GRANT: usp_consultar_asignaturas_ambito_consolidado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_docentes_ambito_consolidado', N'P') IS NULL
    THROW 52312, 'W2A_RUNTIME_GRANT: usp_consultar_docentes_ambito_consolidado requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_ambito_consolidado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_docentes_ambito_consolidado] TO [rol_asistencias_runtime];
GO
