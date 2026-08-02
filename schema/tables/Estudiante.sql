USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Estudiante]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Estudiante] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Estudiante] ADD CONSTRAINT [PK_Estudiante] PRIMARY KEY CLUSTERED ([id]);
END
GO
