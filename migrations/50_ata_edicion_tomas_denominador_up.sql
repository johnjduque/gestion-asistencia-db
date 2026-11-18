-- ============================================================================
-- MIGRACION UP 50: ATA D4 + D2 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS A y B), edicion de tomas durante la sesion y denominador por horas del periodo
--   1. ASISTENCIA/MARGEN_RETARDO_MINUTOS: el valor por defecto pasa a 0 (la ventana de la sesion cierra al terminar y el cierre automatico de
--      tomas ocurre a la hora de fin). Si el valor vigente es el sembrado antes (30) pasa a 0; si un administrador lo cambio a otro valor, se
--      respeta. Sigue en la lista blanca editable.
--   2. Los cuerpos de los SP y de las vistas (se elimina TOM_012 de usp_registrar_asistencias_toma, esEditable / editableHastaUtc de
--      usp_consultar_tomas_sesion, cuentaParaPeriodo / sesionesPeriodo / horasPeriodo en las vistas de cumplimiento y resumen y el denominador de los
--      SP de comparativas, KPI y consolidado) se despliegan con deploy_schema.ps1 (CREATE OR ALTER), como en la 48 y la 49. Firmas y
--      resultsets sin cambio salvo columnas nuevas al final. El mensaje TOM_012 se conserva en el catalogo.
-- Idempotente. Down: 50_ata_edicion_tomas_denominador_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 50 UP: ATA D4 + D2 (margen de retardo 0 y denominador por periodo)';
GO
UPDATE [dbo].[CatalogoParametro]
SET    [valor] = IIF([valor] = N'30', N'0', [valor]),
       [valorDefecto] = N'0',
       [fechaModificacion] = SYSUTCDATETIME()
WHERE  [grupo] = 'ASISTENCIA' AND [clave] = 'MARGEN_RETARDO_MINUTOS'
  AND  ([valorDefecto] <> N'0' OR [valor] = N'30');
GO
IF NOT EXISTS (SELECT 1 FROM [dbo].[CatalogoParametro] WHERE [grupo] = 'ASISTENCIA' AND [clave] = 'MARGEN_RETARDO_MINUTOS' AND [valorDefecto] = N'0')
    THROW 55001, 'MIGRACION 50: el valor por defecto de ASISTENCIA/MARGEN_RETARDO_MINUTOS no quedo en 0.', 1;
GO
PRINT 'MIGRACION 50 UP OK';
GO
