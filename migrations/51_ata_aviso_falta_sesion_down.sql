-- ============================================================================
-- MIGRACION DOWN 51: retira ATA D1 (aviso de falta por sesion)
--   Borra los SP usp_consultar_sesiones_pendientes_aviso_falta, usp_consultar_faltas_sesion_aviso y usp_registrar_aviso_falta_sesion, la tabla
--   AvisoFaltaSesion (se pierde la marca de sesiones ya avisadas: un nuevo up volveria a avisar las sesiones dentro del atraso maximo) y los
--   parametros del grupo AVISO_FALTA_SESION. La plantilla FALTA_ASISTENCIA_SESION_ESTUDIANTE y sus marcadores se conservan (el outbox puede
--   referenciar avisos ya emitidos), como en la 46. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 51 DOWN: retira ATA D1';
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_falta];
GO
IF OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_faltas_sesion_aviso];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_aviso_falta_sesion];
GO
IF OBJECT_ID(N'dbo.AvisoFaltaSesion', N'U') IS NOT NULL
    DROP TABLE [dbo].[AvisoFaltaSesion];
GO
DELETE FROM [dbo].[CatalogoParametro] WHERE [grupo] = 'AVISO_FALTA_SESION';
GO
PRINT 'MIGRACION 51 DOWN OK';
GO
