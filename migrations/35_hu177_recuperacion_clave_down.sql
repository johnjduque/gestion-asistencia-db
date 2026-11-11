-- ============================================================================
-- MIGRACION DOWN 35: HU177 - retira la recuperacion de contrasena
--   1. DROP de los 4 SP.
--   2. DROP de dbo.TokenRecuperacionClave (el FK y el indice se van con ella). Los enlaces pendientes se pierden: dejan de servir.
--   3. Borra la plantilla RECUPERACION_CLAVE y sus marcadores, los mensajes RCL_001..RCL_003 y los parametros RECUPERACION_CLAVE.
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 35 DOWN: retira la recuperacion de contrasena';
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
PRINT 'MIGRACION 35 DOWN OK';
GO
