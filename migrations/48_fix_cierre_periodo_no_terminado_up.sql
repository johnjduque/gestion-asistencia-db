-- ============================================================================
-- MIGRACION UP 48: FIX-CIERRE-002, mensaje PER_007 (el cierre masivo solo se ejecuta sobre un periodo terminado)
--   usp_ejecutar_cierre_masivo_periodo responde PER_007 si el periodo aun no termino. Siembra el texto de usuario y el tecnico
--   (los mismos de schema/seed/17_mensajes_periodo_academico.sql) en bases existentes; el cuerpo del SP se despliega con
--   deploy_schema (CREATE OR ALTER). Idempotente. Down: 48_fix_cierre_periodo_no_terminado_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 48 UP: FIX-CIERRE-002 (PER_007)';
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_007', 'BUSINESS_ERROR', 'MEDIO', N'El período académico aún no ha finalizado; el cierre masivo solo puede ejecutarse después de su fecha de fin ({}).')
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
    ('PER_007', 'BUSINESS_ERROR', 'MEDIO', N'Regla: uv_periodo_academico.estado del periodo no es CERRADO (fecha local institucional <= fechaFin {}); usp_ejecutar_cierre_masivo_periodo no cierra ni audita nada.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
PRINT 'MIGRACION 48 UP: completada';
GO
