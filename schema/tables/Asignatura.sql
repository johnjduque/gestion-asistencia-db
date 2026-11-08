USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Asignatura]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Asignatura] (
    [id] uniqueidentifier NOT NULL,
    [codigo] nvarchar(50) NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [credito] int NOT NULL,
    [area] uniqueidentifier NOT NULL,
    [componente] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Asignatura] ADD CONSTRAINT [PK__Asignatu__3213E83F67AE2274] PRIMARY KEY CLUSTERED ([id]);
END

-- CULM-001 B2NM (DEC-019): codigo unico global; la pertenencia a planes vive en AsignaturaPlanEstudio.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Asignatura_codigo' AND object_id = OBJECT_ID('dbo.Asignatura'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Asignatura_codigo ON dbo.Asignatura (codigo);
GO
