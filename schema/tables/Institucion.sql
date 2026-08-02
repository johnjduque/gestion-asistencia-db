USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Institucion]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Institucion] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Institucion] ADD CONSTRAINT [PK__Instituc__3213E83FB2F1EF7B] PRIMARY KEY CLUSTERED ([id]);
END
GO
