-- ============================================================================
-- MIGRACION UP 36: retiro del flujo propio de recuperacion de contrasena (HU177)
-- Decision de John (2026-11-11): recuperar la contrasena es del servicio de seguridad de terceros, no de esta aplicacion.
-- La migracion 35 (tabla TokenRecuperacionClave, cuatro SP, mensajes RCL_001..003, parametros RECUPERACION_CLAVE y plantilla de
-- correo) estuvo en develop unas horas y se retiro del repositorio. Esta migracion limpia los ambientes donde se alcanzo a
-- aplicar; donde no se aplico no hace nada. Solo elimina objetos y semillas de ese flujo. Idempotente.
-- Down: 36_hu177_retiro_recuperacion_clave_down.sql (no recrea nada: el flujo ya no existe en el repositorio).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 36 UP: retiro del flujo propio de recuperacion de contrasena';
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitud_recuperacion_clave', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_solicitud_recuperacion_clave;
GO
IF OBJECT_ID(N'dbo.usp_emitir_token_recuperacion_clave', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_emitir_token_recuperacion_clave;
GO
IF OBJECT_ID(N'dbo.usp_consultar_token_recuperacion_clave', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_token_recuperacion_clave;
GO
IF OBJECT_ID(N'dbo.usp_consumir_token_recuperacion_clave', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consumir_token_recuperacion_clave;
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NOT NULL DROP TABLE dbo.TokenRecuperacionClave;
GO
DELETE FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE';
DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE';
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003');
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE';
GO
PRINT 'MIGRACION 36 UP OK';
GO
