USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Coordinador]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Coordinador] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Coordinador] ADD CONSTRAINT [PK_Coordinador] PRIMARY KEY CLUSTERED ([id]);
END
GO
