USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W1B (punto 3): permiso del runtime para el directorio paginado de coordinadores de la facultad del decano.
-- El SP valida el perfil DECANO y limita las filas a su facultad. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_coordinadores_facultad_paginado', N'P') IS NULL
    THROW 52301, 'W1B_RUNTIME_GRANT: usp_consultar_coordinadores_facultad_paginado requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_coordinadores_facultad_paginado] TO [rol_asistencias_runtime];
GO
