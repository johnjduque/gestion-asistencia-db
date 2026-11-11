USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: el rol runtime solo ejecuta los cuatro SP de la recuperacion de contrasena; no tiene DML sobre la tabla del enlace.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'GRANT EXECUTE ON [dbo].' + QUOTENAME(o.nombre) + N' TO [rol_asistencias_runtime];'
FROM (VALUES (N'usp_consultar_solicitud_recuperacion_clave'), (N'usp_emitir_token_recuperacion_clave'),
             (N'usp_consultar_token_recuperacion_clave'), (N'usp_consumir_token_recuperacion_clave')) o(nombre)
WHERE OBJECT_ID(N'dbo.' + o.nombre, N'P') IS NOT NULL;
EXEC sys.sp_executesql @sql;
GO
