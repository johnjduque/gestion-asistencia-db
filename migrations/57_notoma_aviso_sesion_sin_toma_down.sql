-- ============================================================================
-- MIGRACION DOWN 57: retira NOTOMA-001 (aviso de sesion sin toma al coordinador)
--   Borra los SP usp_consultar_sesiones_pendientes_aviso_sin_toma, usp_consultar_destinatarios_aviso_sin_toma y usp_registrar_aviso_sesion_sin_toma,
--   la tabla AvisoSesionSinToma (se pierde la marca de sesiones ya avisadas: un nuevo up volveria a avisar las sesiones dentro del atraso maximo) y
--   los parametros del grupo AVISO_SESION_SIN_TOMA. La plantilla SESION_SIN_TOMA_COORDINADOR y sus marcadores se conservan (el outbox puede
--   referenciar avisos ya emitidos), como en la 51. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 57 DOWN: retira NOTOMA-001';
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_destinatarios_aviso_sin_toma];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_aviso_sesion_sin_toma];
GO
IF OBJECT_ID(N'dbo.AvisoSesionSinToma', N'U') IS NOT NULL
    DROP TABLE [dbo].[AvisoSesionSinToma];
GO
DELETE FROM [dbo].[CatalogoParametro] WHERE [grupo] = 'AVISO_SESION_SIN_TOMA';
GO
PRINT 'MIGRACION 57 DOWN OK';
GO
