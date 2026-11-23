USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Grupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Grupo] (
    [id] uniqueidentifier NOT NULL,
    [asignatura] uniqueidentifier NOT NULL,
    [periodoAcademico] uniqueidentifier NOT NULL,
    [codigo] int NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [cantidadEstudiantes] int NOT NULL,
    [cantidadEstudiantesFinalizaron] int NOT NULL,
    [cantidadEstudiantesCancelaronVoluntadPropia] int NOT NULL,
    [cantidadEstudiantesCancelaronAutomaticamente] int NOT NULL,
    [docente] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [PK__Grupo__3213E83FFA8811CC] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Grupo')
      AND name IN (N'au' + N'la')
)
    THROW 50005, 'SCHEMA_CONTRACT_CONFLICT: dbo.Grupo contains ghost columns outside DB-GP-001.', 1;
GO

-- PERF-EST-MM: las consultas del estudiante y del coordinador filtran los grupos por asignatura (g.asignatura = @idMateria).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_Asignatura')
    CREATE NONCLUSTERED INDEX IX_Grupo_Asignatura ON dbo.Grupo (asignatura) INCLUDE (periodoAcademico, docente);
GO

-- DEC-077 (2026-11-20): programa responsable del grupo. Es el programa del coordinador que lo crea; en un grupo compartido por
-- varios programas solo su coordinador gestiona el grupo, aprueba sus sesiones y recibe los avisos del grupo. NULL en grupos
-- anteriores: dbo.ufn_programa_responsable_grupo lo resuelve igual (ver la funcion). FK en zz_foreign_keys.sql.
IF COL_LENGTH('dbo.Grupo', 'programaResponsable') IS NULL
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD [programaResponsable] uniqueidentifier NULL;
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_docente')
    CREATE NONCLUSTERED INDEX IX_Grupo_docente ON dbo.Grupo (docente);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_periodoAcademico')
    CREATE NONCLUSTERED INDEX IX_Grupo_periodoAcademico ON dbo.Grupo (periodoAcademico);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_programaResponsable')
    CREATE NONCLUSTERED INDEX IX_Grupo_programaResponsable ON dbo.Grupo (programaResponsable);
GO
