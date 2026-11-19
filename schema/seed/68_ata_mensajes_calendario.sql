USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D7: mensaje del rango del calendario de sesiones (horario semanal con fechas). Idempotente (MERGE por codigo).
--   CAL_001  el rango no es valido: debe tener ambas fechas, hasta >= desde y como maximo 31 dias (el texto de usuario no lleva parametros)
-- Migracion: 52_ata_solicitudes_docente_calendario_up.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('CAL_001', 'VALIDATION_ERROR', 'BAJO', N'El rango de fechas no es válido: indique inicio y fin, con el fin igual o posterior y máximo 31 días.')
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
    ('CAL_001', 'VALIDATION_ERROR', 'BAJO', N'ATA D7: rango [{}] a [{}] inválido (fechas ausentes, hasta < desde o más de {} días).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
