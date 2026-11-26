-- SKILLS-BD lote 16 (2026-11-26): pruebas que faltaban de la migracion 76 y de las pistas de rendimiento de los KPI (hallazgo 2 del code
-- review de develop). Lo ejecuta test/test_perf_migracion_76.ps1 con sqlcmd y la variable MIGDIR. Parte de una BD ya desplegada desde
-- schema/ (DetalleAsistencia.sql ya crea el indice). La parte de la migracion ocurre dentro de UNA transaccion que se revierte.
--   PERF_HINTS_OK          las pistas que sostienen los tiempos de los KPI siguen en sus SP (RECOMPILE, NO_PERFORMANCE_SPOOL, FORCESEEK)
--                          y cada FORCESEEK tiene el indice unico por el que busca
--   PERF_MIG76_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   PERF_MIG76_DOWN_OK     el down retira solo el indice cubriente (dos veces sin error)
--   PERF_MIG76_UP2_OK      el up (dos veces) deja el indice con clave (asistencia) e INCLUDE (razonCausa, asistio)
--   PERF_MIG76_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
-- Pistas: numero minimo de apariciones de cada una en su SP
DECLARE @pistas TABLE (sp SYSNAME NOT NULL, pista NVARCHAR(100) NOT NULL, minimo INT NOT NULL);
INSERT INTO @pistas (sp, pista, minimo) VALUES
    (N'usp_consultar_kpis_coordinador', N'OPTION (RECOMPILE)', 2),
    (N'usp_consultar_alerta_temprana_programa', N'OPTION (RECOMPILE)', 1),
    (N'usp_consultar_kpis_decano', N'OPTION (NO_PERFORMANCE_SPOOL)', 2),
    (N'usp_consultar_kpis_institucion', N'OPTION (NO_PERFORMANCE_SPOOL)', 2),
    (N'usp_registrar_asistencia_por_token', N'WITH (FORCESEEK)', 2);
IF EXISTS (SELECT 1 FROM @pistas p
           CROSS APPLY (SELECT d = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + p.sp, N'P'))) o
           WHERE o.d IS NULL OR (LEN(o.d) - LEN(REPLACE(o.d, p.pista, N''))) / LEN(p.pista) < p.minimo)
    THROW 53053, 'TEST FAILED: PERF_HINTS falta una pista de rendimiento en los SP de KPI o en el registro por QR.', 1;
-- FORCESEEK de usp_registrar_asistencia_por_token: indices unicos (estudianteGrupo, sesion) y (asistencia, toma)
IF NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = OBJECT_ID(N'dbo.Asistencia') AND i.is_unique = 1
               AND (SELECT STRING_AGG(c.name, N',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic
                    INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal > 0) = N'estudianteGrupo,sesion')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND i.is_unique = 1
               AND (SELECT STRING_AGG(c.name, N',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic
                    INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal > 0) = N'asistencia,toma')
    THROW 53054, 'TEST FAILED: PERF_HINTS un FORCESEEK no tiene su indice unico.', 1;
PRINT 'PERF_HINTS_OK';
GO
-- Forma del indice cubriente: 'asistencia|asistio,razonCausa' (clave | INCLUDE en orden alfabetico), '' si no existe
IF OBJECT_ID('tempdb..#forma76') IS NOT NULL DROP PROCEDURE #forma76;
GO
CREATE PROCEDURE #forma76 @forma NVARCHAR(400) OUTPUT
AS
BEGIN
    SET @forma = N'';
    SELECT @forma = CONCAT(
        (SELECT STRING_AGG(c.name, N',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic
         INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal > 0), N'|',
        (SELECT STRING_AGG(c.name, N',') WITHIN GROUP (ORDER BY c.name) FROM sys.index_columns ic
         INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1))
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND i.name = N'IX_DetalleAsistencia_Asistencia_Cobertura';
END;
GO
IF OBJECT_ID('tempdb..#indices76') IS NOT NULL DROP TABLE #indices76;
SELECT name INTO #indices76 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia') AND name <> N'IX_DetalleAsistencia_Asistencia_Cobertura';
GO
BEGIN TRANSACTION;
GO
DECLARE @f NVARCHAR(400);
EXEC #forma76 @forma = @f OUTPUT;
IF @f <> N'asistencia|asistio,razonCausa'
    THROW 53055, 'TEST FAILED: PERF_MIG76 la base inicial no tiene el indice cubriente (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/76_perf_detalle_asistencia_cobertura_up.sql
GO
DECLARE @f NVARCHAR(400);
EXEC #forma76 @forma = @f OUTPUT;
IF @f <> N'asistencia|asistio,razonCausa'
    THROW 53056, 'TEST FAILED: PERF_MIG76 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'PERF_MIG76_UP1_OK';
GO
:r $(MIGDIR)/76_perf_detalle_asistencia_cobertura_down.sql
GO
:r $(MIGDIR)/76_perf_detalle_asistencia_cobertura_down.sql
GO
DECLARE @f NVARCHAR(400);
EXEC #forma76 @forma = @f OUTPUT;
IF @f <> N''
   OR EXISTS (SELECT name FROM #indices76 EXCEPT SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
    THROW 53057, 'TEST FAILED: PERF_MIG76 el down no retiro el indice cubriente o retiro otro indice.', 1;
PRINT 'PERF_MIG76_DOWN_OK';
GO
:r $(MIGDIR)/76_perf_detalle_asistencia_cobertura_up.sql
GO
:r $(MIGDIR)/76_perf_detalle_asistencia_cobertura_up.sql
GO
DECLARE @f NVARCHAR(400);
EXEC #forma76 @forma = @f OUTPUT;
IF @f <> N'asistencia|asistio,razonCausa'
   OR EXISTS (SELECT name FROM #indices76 EXCEPT SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
    THROW 53058, 'TEST FAILED: PERF_MIG76 el up no dejo el indice cubriente con su forma.', 1;
PRINT 'PERF_MIG76_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
DECLARE @f NVARCHAR(400);
EXEC #forma76 @forma = @f OUTPUT;
IF @@TRANCOUNT <> 0 OR @f <> N'asistencia|asistio,razonCausa'
    THROW 53059, 'TEST FAILED: PERF_MIG76 la transaccion no se revirtio.', 1;
PRINT 'PERF_MIG76_ROLLBACK_OK';
GO
