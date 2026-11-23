USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Revision final P3 (2026-11-22): mensajes de las reglas nuevas de periodos y de matricula manual. Idempotente (MERGE por codigo). Migracion 69.
--   PER_012 (BD-3)  las fechas del periodo se solapan con otro periodo de la institucion (nombre del periodo en conflicto)
--   EST_010 (BD-4)  matricula manual: el estudiante existente no pertenece a ningun programa del grupo
--   EST_011 (BD-4)  matricula manual: el programa indicado no es uno de los programas del estudiante
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_012', 'BUSINESS_ERROR', 'MEDIO', N'Las fechas del período se cruzan con el período {}; los períodos de la institución no pueden solaparse.'),
    ('EST_010', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante no pertenece a ningún programa de este grupo; solo puedes matricular estudiantes de los programas del grupo.'),
    ('EST_011', 'BUSINESS_ERROR', 'MEDIO', N'El programa indicado no es uno de los programas del estudiante; elige uno de sus programas del grupo.')
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
    ('PER_012', 'BUSINESS_ERROR', 'MEDIO', N'Regla: las fechas se solapan con dbo.PeriodoAcademico [{}] de la misma institucion (inicio <= fin existente y fin >= inicio existente); sin escrituras.'),
    ('EST_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla BD-4: el estudiante tiene dbo.EstudiantePrograma pero ninguno es programa del grupo (ufn_programas_grupo); sin escrituras.'),
    ('EST_011', 'BUSINESS_ERROR', 'MEDIO', N'Regla BD-4: idPrograma esta en el grupo pero no figura en dbo.EstudiantePrograma del estudiante; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
