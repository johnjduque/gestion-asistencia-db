USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[EstudiantePrograma]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[EstudiantePrograma] (
    [id] uniqueidentifier NOT NULL,
    [estudiante] uniqueidentifier NOT NULL,
    [programa] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[EstudiantePrograma] ADD CONSTRAINT [PK_EstudiantePrograma] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 B2NM (DEC-020): un vinculo por (estudiante, programa).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_EstudiantePrograma_estudiante_programa' AND object_id = OBJECT_ID('dbo.EstudiantePrograma'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_EstudiantePrograma_estudiante_programa ON dbo.EstudiantePrograma (estudiante, programa);
GO

-- Migracion 63: semestre que cursa el estudiante en el programa (lo registra el coordinador; NULL = sin informar). El rango lo valida
-- usp_actualizar_semestre_estudiante_programa contra el catalogo dbo.Semestre.
IF COL_LENGTH('dbo.EstudiantePrograma', 'semestreActual') IS NULL
BEGIN
    ALTER TABLE [dbo].[EstudiantePrograma] ADD [semestreActual] tinyint NULL;
END
GO
