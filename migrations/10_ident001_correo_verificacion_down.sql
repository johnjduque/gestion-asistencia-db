USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN: IDENT-001. Revierte los objetos de verificacion de correo y el dominio institucional.
-- Tras ejecutarla hay que restaurar usp_registrar_estudiante_en_grupo a su version previa (sin validacion de dominio).
-- ============================================================================

-- 1. SP y funcion del modulo
IF OBJECT_ID(N'dbo.usp_emitir_token_verificacion_correo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_emitir_token_verificacion_correo;
GO
IF OBJECT_ID(N'dbo.usp_consultar_token_verificacion_correo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_token_verificacion_correo;
GO
IF OBJECT_ID(N'dbo.usp_confirmar_verificacion_correo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_confirmar_verificacion_correo;
GO
IF OBJECT_ID(N'dbo.usp_consultar_reenvio_verificacion_correo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_reenvio_verificacion_correo;
GO
IF OBJECT_ID(N'dbo.ufn_correo_cumple_dominio_institucional', N'FN') IS NOT NULL DROP FUNCTION dbo.ufn_correo_cumple_dominio_institucional;
GO

-- 2. Tabla (el FK y el indice se eliminan con ella)
IF OBJECT_ID(N'dbo.TokenVerificacionCorreo', N'U') IS NOT NULL DROP TABLE dbo.TokenVerificacionCorreo;
GO

-- 3. Plantilla, marcadores, mensajes y parametros
DELETE FROM dbo.PlantillaNotificacion WHERE tipo = 'VERIFICACION_CORREO';
DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'VERIFICACION_CORREO';
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('VCE_001','VCE_002','VCE_003','VCE_004','VCE_005','VCE_006','VCE_007');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('VCE_001','VCE_002','VCE_003','VCE_004','VCE_005','VCE_006','VCE_007');
DELETE FROM dbo.CatalogoParametro WHERE (grupo = 'REGISTRO' AND clave = 'DOMINIO_CORREO_ESTUDIANTE') OR grupo = 'VERIFICACION_CORREO';
GO
