USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Programa]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Programa] (
    [id] uniqueidentifier NOT NULL,
    [facultad] uniqueidentifier NOT NULL,
    [tipoDePrograma] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [coordinador] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [PK__Programa__3213E83F41C65B8B] PRIMARY KEY CLUSTERED ([id]);
END
GO
