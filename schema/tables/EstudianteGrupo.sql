USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[EstudianteGrupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[EstudianteGrupo] (
    [id] uniqueidentifier NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [estudiante] uniqueidentifier NOT NULL,
    [grupo] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[EstudianteGrupo] ADD CONSTRAINT [PK__Estudian__3213E83F84F4715A] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- PERF-EST-MM (docs/work-items/PERF-estudiante-mis-materias/PLAN.md): las vistas del estudiante filtran las matriculas por
-- estudiante (uv_estudiante_grupo, uv_materia_estudiante, sesiones de la materia) y unen por grupo (uv_sesion_estudiante_reclamo,
-- resumenes por grupo). Sin estos indices cada consulta recorre la tabla completa.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_Estudiante')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_Estudiante ON dbo.EstudianteGrupo (estudiante) INCLUDE (grupo, estado);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_Grupo')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_Grupo ON dbo.EstudianteGrupo (grupo) INCLUDE (estudiante, estado);
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_estado')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_estado ON dbo.EstudianteGrupo (estado);
GO
