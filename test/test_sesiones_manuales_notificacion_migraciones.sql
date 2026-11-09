-- CULM-001 / DEC-064: migracion 29 (sesiones manuales: aviso y cancelacion por el coordinador) up -> down -> up.
-- Lo ejecuta test/test_sesiones_manuales_notificacion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de
-- UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_SMN_DOWN_OK     el down quita SP, vistas, tabla, mensajes SES_018..021, plantillas, marcadores y parametro
--   MIG_SMN_UP1_OK      el up crea todo
--   MIG_SMN_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_SMN_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_SMN_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#smnmig') IS NOT NULL DROP TABLE #smnmig;
CREATE TABLE #smnmig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/29_sesiones_manuales_notificacion_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.MotivoCancelacionSesion', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021'))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR'))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'SESION' AND clave = 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA')
    THROW 58950, 'TEST FAILED: SMN_MIG el down no quito los objetos de las sesiones manuales.', 1;
IF OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NULL
    THROW 58951, 'TEST FAILED: SMN_MIG el down no debe tocar los objetos de B.1.', 1;
PRINT 'MIG_SMN_DOWN_OK';
GO
:r $(MIGDIR)/29_sesiones_manuales_notificacion_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NULL
   OR OBJECT_ID(N'dbo.MotivoCancelacionSesion', N'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021')) <> 4
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021')) <> 4
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE activa = 1 AND tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')) <> 2
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')) <> 14
   OR (SELECT COUNT(*) FROM dbo.MotivoCancelacionSesion WHERE estaActivo = 1) <> 5
   OR dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA') <> 250
    THROW 58952, 'TEST FAILED: SMN_MIG el up no dejo los objetos de las sesiones manuales.', 1;
INSERT #smnmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN (N'usp_consultar_destinatarios_sesion_manual', N'usp_cancelar_sesion_coordinador', N'usp_consultar_motivos_cancelacion_sesion',
                 N'uv_sesion_manual', N'uv_motivo_cancelacion_sesion');
IF (SELECT COUNT(*) FROM #smnmig) <> 5 THROW 58953, 'TEST FAILED: SMN_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_SMN_UP1_OK';
GO
:r $(MIGDIR)/29_sesiones_manuales_notificacion_up.sql
GO
IF EXISTS (SELECT 1 FROM #smnmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.MotivoCancelacionSesion) <> 5
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')) <> 14
    THROW 58954, 'TEST FAILED: SMN_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_SMN_UP2_OK';
GO
:r $(MIGDIR)/29_sesiones_manuales_notificacion_down.sql
GO
:r $(MIGDIR)/29_sesiones_manuales_notificacion_up.sql
GO
IF EXISTS (SELECT 1 FROM #smnmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR OBJECT_ID(N'dbo.MotivoCancelacionSesion', N'U') IS NULL
    THROW 58955, 'TEST FAILED: SMN_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_SMN_DOWN_UP_OK';
GO
IF @@TRANCOUNT <> 1 THROW 58956, 'TEST FAILED: SMN_MIG la migracion altero el nivel de transacciones.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_SMN_ROLLBACK_OK';
GO
