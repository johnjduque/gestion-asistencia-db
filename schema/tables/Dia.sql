USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Dia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Dia] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(2) NOT NULL
);

ALTER TABLE [dbo].[Dia] ADD CONSTRAINT [PK_Dia] PRIMARY KEY CLUSTERED ([id]);
END
GO
