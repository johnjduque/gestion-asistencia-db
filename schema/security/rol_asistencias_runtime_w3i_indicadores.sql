USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W3I: permiso del runtime para el resumen de grupos del docente (totales de su tablero y de su lista de grupos). El SP valida
-- el perfil DOCENTE y acota por titularidad dentro de su propio cuerpo. Los KPI de coordinador, decano y administrador ya tenian
-- permiso (solo ganan columnas). Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_resumen_grupos_docente', N'P') IS NULL
    THROW 52331, 'W3I_RUNTIME_GRANT: usp_consultar_resumen_grupos_docente requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_resumen_grupos_docente] TO [rol_asistencias_runtime];
GO
