USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Semestre actual del estudiante en el programa (usp_actualizar_semestre_estudiante_programa). Idempotente (MERGE por codigo).
--   EST_007  exito: el semestre quedo actualizado
--   EST_008  el estudiante no esta vinculado al programa
--   EST_009  semestre fuera del rango del catalogo dbo.Semestre (parametros: minimo y maximo)
-- Migracion: 63_semestre_actual_estudiante_programa_up.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('EST_007', 'SUCCESS',          'BAJO',  N'El semestre del estudiante quedó actualizado.'),
    ('EST_008', 'BUSINESS_ERROR',   'MEDIO', N'El estudiante no está vinculado a este programa académico.'),
    ('EST_009', 'VALIDATION_ERROR', 'BAJO',  N'El semestre debe estar entre {} y {}.')
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
    ('EST_007', 'SUCCESS',          'BAJO',  N'EstudiantePrograma.semestreActual actualizado por el coordinador del programa (NULL lo limpia).'),
    ('EST_008', 'BUSINESS_ERROR',   'MEDIO', N'Regla: no existe dbo.EstudiantePrograma para el estudiante y el programa indicados.'),
    ('EST_009', 'VALIDATION_ERROR', 'BAJO',  N'Regla: @semestreActual fuera del rango [MIN(Semestre.numero), MAX(Semestre.numero)] del catalogo dbo.Semestre.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
