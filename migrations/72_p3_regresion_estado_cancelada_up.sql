-- ============================================================================
-- MIGRACION UP 72: regresion P3 (2026-11-22), D2. Siembra el rotulo RPT_ASISTENCIA_ESTADO_CANCELADA (usuario y tecnico) que el Excel del
-- reporte de asistencia escribe en las filas de una sesion cancelada (antes salian como SIN REGISTRO). Los SP y vistas del D1/D2 se despliegan
-- con deploy_schema.ps1 (CREATE OR ALTER). Idempotente. Down: 72_p3_regresion_estado_cancelada_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET QUOTED_IDENTIFIER ON;
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('RPT_ASISTENCIA_ESTADO_CANCELADA', 'INFORMATIVO', 'BAJO', N'CANCELADA')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('RPT_ASISTENCIA_ESTADO_CANCELADA', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): texto del estado «CANCELADA» (sesión cancelada) en la columna Estado de asistencia del libro de Excel.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
PRINT 'MIGRACION 72 UP: completada';
GO
