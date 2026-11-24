-- ============================================================================
-- MIGRACION UP 76: PERF indice cubriente dbo.DetalleAsistencia (asistencia) INCLUDE (razonCausa, asistio)
--   uv_asistencia_sesion_horas lee por cabecera (OUTER APPLY sobre DetalleAsistencia WHERE asistencia = a.id) razonCausa y asistio; con el indice
--   UX_DetalleAsistencia_Asistencia_Toma (asistencia, toma) el plan escaneaba el clustered por cada fila (13 s en uv_resumen_asistencia_estudiante_grupo
--   con 6.3 mil matriculas; 0.3 s con el indice). Down: 76_perf_detalle_asistencia_cobertura_down.sql.
-- Sin cambios de columnas, datos ni comportamiento. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 76 UP: indice cubriente de DetalleAsistencia';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DetalleAsistencia') AND name = 'IX_DetalleAsistencia_Asistencia_Cobertura')
    CREATE NONCLUSTERED INDEX IX_DetalleAsistencia_Asistencia_Cobertura ON dbo.DetalleAsistencia (asistencia) INCLUDE (razonCausa, asistio);
GO
