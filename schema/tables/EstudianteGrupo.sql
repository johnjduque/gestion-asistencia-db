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
