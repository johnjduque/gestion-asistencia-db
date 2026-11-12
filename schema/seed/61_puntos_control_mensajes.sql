USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B): mensajes del ciclo de vida de la toma y del
-- reclamo por toma. Idempotente (MERGE por codigo).
--   TOM_012 la toma cerrada ya no se puede corregir porque se abrio la siguiente (409).
--   REV_026 la toma reclamada no tiene ausencia (SJC) del estudiante (409).
--   REV_027 ya existe un reclamo no retirado para esa toma (409).
--   REV_028 resultado de aprobacion distinto de PRESENTE (AN) o JUSTIFICADA (EX) (400).
--   REV_029 la aprobacion como presente solo aplica a reclamos de una toma (409).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('TOM_012', 'BUSINESS_ERROR',   'MEDIO', N'La toma {} ya no se puede corregir porque se abrió la toma {}. Las correcciones se hacen por reclamo del estudiante.'),
    ('REV_026', 'BUSINESS_ERROR',   'MEDIO', N'Solo puedes reclamar una toma en la que quedaste ausente.'),
    ('REV_027', 'BUSINESS_ERROR',   'MEDIO', N'Ya existe un reclamo para esta toma.'),
    ('REV_028', 'VALIDATION_ERROR', 'BAJO',  N'El resultado de la aprobación debe ser PRESENTE o JUSTIFICADA.'),
    ('REV_029', 'BUSINESS_ERROR',   'MEDIO', N'La aprobación como presente solo aplica a reclamos de una toma.')
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
    ('TOM_012', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la toma numero [{}] esta cerrada y ya se abrio la toma numero [{}]; solo se corrige por reclamo; sin escrituras.'),
    ('REV_026', 'BUSINESS_ERROR',   'MEDIO', N'Regla: el estudiante no tiene SJC en la toma [{}] de la sesion [{}]; sin escrituras.'),
    ('REV_027', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la toma [{}] ya tiene la solicitud de revision no retirada [{}]; sin escrituras.'),
    ('REV_028', 'VALIDATION_ERROR', 'BAJO',  N'Validacion: codigoResultadoAprobacion [{}] fuera de ASISTENCIA/CODIGO_RAZON_PRESENTE y ASISTENCIA/CODIGO_RAZON_EXCUSA; sin escrituras.'),
    ('REV_029', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la solicitud de revision [{}] es de la sesion completa (sin toma) y solo admite el resultado EX; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
