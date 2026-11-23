-- ============================================================================
-- MIGRACION DOWN 73: retira la sincronizacion de parametros del Catalogo externo (INT-004). Idempotente.
--   Borra los SP, la bitacora SincronizacionParametroExterno y los mensajes PRM_013..PRM_016. NO revierte los valores ya copiados en
--   dbo.CatalogoParametro (se conservan, igual que el down de la 22).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_parametro_catalogo_externo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_sincronizar_parametro_catalogo_externo];
GO
IF OBJECT_ID(N'dbo.usp_validar_valor_parametro_externo_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_valor_parametro_externo_interno];
GO
IF OBJECT_ID(N'dbo.SincronizacionParametroExterno', N'U') IS NOT NULL
    DROP TABLE [dbo].[SincronizacionParametroExterno];
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016');
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016');
GO
PRINT 'MIGRACION 73 DOWN: completada';
GO
