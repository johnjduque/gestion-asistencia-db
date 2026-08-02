USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Perfil]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Perfil] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(100) NOT NULL,
    [nivel_acceso] int NOT NULL,
    [codigo] nvarchar(2) NOT NULL
);

ALTER TABLE [dbo].[Perfil] ADD CONSTRAINT [PK_Perfil] PRIMARY KEY CLUSTERED ([id]);
END
GO
