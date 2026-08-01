USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Facultad]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Facultad] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [institucion] uniqueidentifier NOT NULL,
    [decano] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Facultad] ADD CONSTRAINT [PK__Facultad__3213E83FEA2EF79E] PRIMARY KEY CLUSTERED ([id]);
END
GO
