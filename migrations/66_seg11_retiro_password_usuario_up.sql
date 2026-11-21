-- ============================================================================
-- MIGRACION UP 66: SEG-11 - retiro de la columna dbo.Usuario.password
--   La identidad (credenciales, claves, hashes) la administra Keycloak / Security Baseline; la BD no guarda credenciales. IDENT-002
--   ya dejo de crear usuarios con clave propia. Esta migracion:
--   1. Quita cualquier DEFAULT de la columna y la columna Usuario.password (los hashes guardados se pierden: no se usaban para autenticar).
--   Los cuerpos nuevos de uv_usuario (sin password), uv_administrador (sin passwordUsuario), uv_usuario_autenticacion (sin password),
--   usp_sincronizar_usuario_interno (ya no exige ni inserta la clave), usp_admitir_estudiante (ya no exige la clave, ADS_006),
--   usp_internal_matricular_por_token (ya no exige @password) y usp_vincular_docente_programa (el modo ya no depende de @password)
--   se despliegan con deploy_schema.ps1 (CREATE OR ALTER), como en la 56. Los parametros @password de los SP publicos se conservan,
--   obsoletos e ignorados, para no romper las firmas. Entre esta migracion y el despliegue, las vistas y SP viejos que leian o
--   escribian la columna quedan invalidos: el despliegue es obligatorio (docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md).
-- Idempotente. Down: 66_seg11_retiro_password_usuario_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 66 UP: SEG-11 retiro de dbo.Usuario.password';
GO
DECLARE @df SYSNAME = (SELECT dc.name FROM sys.default_constraints dc
                       INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
                       WHERE dc.parent_object_id = OBJECT_ID(N'dbo.Usuario') AND c.name = N'password');
IF @df IS NOT NULL
BEGIN
    DECLARE @sqlDf NVARCHAR(400) = N'ALTER TABLE [dbo].[Usuario] DROP CONSTRAINT ' + QUOTENAME(@df) + N';';
    EXEC sys.sp_executesql @sqlDf;
END
GO
IF COL_LENGTH(N'dbo.Usuario', N'password') IS NOT NULL
    ALTER TABLE [dbo].[Usuario] DROP COLUMN [password];
GO
IF COL_LENGTH(N'dbo.Usuario', N'password') IS NOT NULL
    THROW 55701, 'MIGRACION 66: la columna dbo.Usuario.password no se retiro.', 1;
IF OBJECT_ID(N'dbo.Usuario', N'U') IS NULL OR COL_LENGTH(N'dbo.Usuario', N'correo') IS NULL
    THROW 55702, 'MIGRACION 66: dbo.Usuario debe conservarse con sus demas columnas.', 1;
GO
PRINT 'MIGRACION 66 UP OK (ejecute deploy_schema.ps1 para los cuerpos de vistas y SP)';
GO
