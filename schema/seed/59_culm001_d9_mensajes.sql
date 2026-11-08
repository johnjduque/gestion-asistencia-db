USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.9-a (CONTRACT D §11.2, DEC-044): mensajes de los hallazgos medios. Idempotente (MERGE por codigo).
--   DEC_020 (F-ADM-024): la persona ya es decano activo (409).
--   NTF_020 (F-ADM-027): la notificacion que se quiere reintentar no existe (404).
--   NTF_021 (F-ADM-027): el tipo de plantilla no existe (404).
-- No se crea GENERAL/TAMANO_PAGINA_MAXIMO: la paginacion reutiliza PAGINACION/TAMANO_MAXIMO y el mensaje PAG_001 (OBS-15).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('DEC_020', 'BUSINESS_ERROR', 'MEDIO', N'La persona ya está registrada como decano.'),
    ('NTF_020', 'BUSINESS_ERROR', 'MEDIO', N'La notificación no existe.'),
    ('NTF_021', 'BUSINESS_ERROR', 'MEDIO', N'El tipo de plantilla no existe.')
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
    ('DEC_020', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la persona ya tiene un registro de Decano activo (Decano.estado = 1); sin escrituras.'),
    ('NTF_020', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: NotificacionSaliente no tiene una fila con el identificador recibido; sin escrituras.'),
    ('NTF_021', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PlantillaNotificacion no tiene el tipo recibido; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
