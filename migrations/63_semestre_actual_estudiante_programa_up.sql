-- ============================================================================
-- MIGRACION UP 63: semestre actual del estudiante en el programa (pantalla "Estudiantes del Programa" del coordinador)
--   La BD no guardaba en que semestre va un estudiante ni el directorio devolvia el nombre del programa: la pantalla mostraba
--   "No informado" en ambos. El coordinador registra el semestre con usp_actualizar_semestre_estudiante_programa.
--   1. Columna dbo.EstudiantePrograma.semestreActual (tinyint NULL; schema/tables/EstudiantePrograma.sql).
--   2. Mensajes EST_007 (exito), EST_008 (estudiante sin vinculo con el programa) y EST_009 (semestre fuera del rango del catalogo
--      dbo.Semestre), usuario y tecnico (seed 71_estudiante_semestre_mensajes.sql).
--   Los cuerpos de usp_actualizar_semestre_estudiante_programa (nuevo, con su GRANT a rol_asistencias_runtime en schema/security) y de
--   usp_consultar_directorio_estudiantes_paginado (columnas idPrograma, nombrePrograma y semestreActual al FINAL del listado) se
--   despliegan con deploy_schema.ps1 (CREATE OR ALTER), como en la 48, la 49, la 56 y la 61.
-- Idempotente. Down: 63_semestre_actual_estudiante_programa_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 63 UP: semestre actual del estudiante en el programa';
GO

IF COL_LENGTH('dbo.EstudiantePrograma', 'semestreActual') IS NULL
BEGIN
    ALTER TABLE [dbo].[EstudiantePrograma] ADD [semestreActual] tinyint NULL;
END
GO

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
PRINT 'MIGRACION 63 UP OK (ejecute deploy_schema.ps1 para los cuerpos de los SP)';
GO
