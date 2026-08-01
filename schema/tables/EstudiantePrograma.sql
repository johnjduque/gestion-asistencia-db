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
