-- ============================================================================
-- MIGRACION DOWN 46: retira IDENT-002 (SP de reenvio de activacion y su permiso). La plantilla ACTIVACION_CUENTA y los
-- mensajes VCE_009, ACT_001 y ACT_002 se conservan (el outbox puede referenciar avisos ya emitidos). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 46 DOWN: retira IDENT-002';
GO
IF OBJECT_ID(N'dbo.usp_consultar_reenvio_activacion_cuenta', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_reenvio_activacion_cuenta];
GO
PRINT 'MIGRACION 46 DOWN OK';
GO
