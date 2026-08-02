USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Administrador]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Administrador] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL,
    [institucion] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Administrador] ADD CONSTRAINT [PK_Administrador] PRIMARY KEY CLUSTERED ([id]);
END
GO
