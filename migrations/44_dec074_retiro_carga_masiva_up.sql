-- ============================================================================
-- MIGRACION UP 44: DEC-074 retiro de la carga masiva de usuarios por CSV (HU171, CULM-001 D.5)
--   Decision del equipo con el asesor, comunicada por el responsable el 2026-11-13: la carga por archivo trae mas problemas
--   que beneficios; decanos, coordinadores y docentes se registran uno por uno (HU117-B, HU120 y HU091).
--   Elimina usp_validar_carga_masiva_usuarios, la vista uv_jerarquia_alta_usuario, la tabla JerarquiaAltaUsuario (con sus
--   FK y sus filas), los parametros CARGA_MASIVA/* (su metadato de edicion y su historial de cambios) y los mensajes CMA_*.
--   Conserva IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO y la firma de usp_crear_coordinador / usp_crear_decano (alta individual).
--   Los usuarios creados por carga masiva se conservan. Idempotente. Down: 44_dec074_retiro_carga_masiva_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 44 UP: DEC-074 retiro de la carga masiva';
GO
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_carga_masiva_usuarios];
GO
IF OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_jerarquia_alta_usuario];
GO
IF OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NOT NULL
    DROP TABLE [dbo].[JerarquiaAltaUsuario];
GO
DELETE c FROM dbo.CambioParametro c
INNER JOIN dbo.CatalogoParametro p ON p.id = c.parametro
WHERE p.grupo = 'CARGA_MASIVA';
DELETE e FROM dbo.CatalogoParametroEdicion e
INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
WHERE p.grupo = 'CARGA_MASIVA';
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'CARGA_MASIVA';
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'CMA[_]___';
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'CMA[_]___';
GO
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    THROW 54401, 'MIGRACION 44: quedaron objetos de la carga masiva.', 1;
IF OBJECT_ID(N'dbo.usp_crear_coordinador', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_crear_decano', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'IDENTIDAD' AND clave = 'TIPO_IDENTIFICACION_DEFECTO')
    THROW 54402, 'MIGRACION 44: la alta individual debe seguir disponible.', 1;
GO
PRINT 'MIGRACION 44 UP OK';
GO
