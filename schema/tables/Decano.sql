USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Decano]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Decano] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Decano] ADD CONSTRAINT [PK_Decano] PRIMARY KEY CLUSTERED ([id]);
END
GO
