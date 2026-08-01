USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Componente]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Componente] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(3) NOT NULL
);

ALTER TABLE [dbo].[Componente] ADD CONSTRAINT [PK_Componente] PRIMARY KEY CLUSTERED ([id]);
END
GO
