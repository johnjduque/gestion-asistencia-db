-- ============================================================================
-- MIGRACION DOWN 76: PERF indice cubriente dbo.DetalleAsistencia (asistencia) INCLUDE (razonCausa, asistio)
--   Elimina IX_DetalleAsistencia_Asistencia_Cobertura (el resto de indices de DetalleAsistencia no se toca).
-- Sin cambios de columnas, datos ni comportamiento. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 76 DOWN: retira el indice cubriente de DetalleAsistencia';
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DetalleAsistencia') AND name = 'IX_DetalleAsistencia_Asistencia_Cobertura')
    DROP INDEX IX_DetalleAsistencia_Asistencia_Cobertura ON dbo.DetalleAsistencia;
GO
