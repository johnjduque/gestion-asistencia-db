-- ============================================================================
-- MIGRACION DOWN 45: retira INT-003 (usp_sincronizar_mensaje_usuario y su permiso). Los textos ya sincronizados en
-- dbo.CatalogoMensajeUsuario se conservan. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 45 DOWN: retira INT-003';
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_mensaje_usuario', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_sincronizar_mensaje_usuario];
GO
PRINT 'MIGRACION 45 DOWN OK';
GO
