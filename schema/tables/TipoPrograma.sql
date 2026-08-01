USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[TipoPrograma]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[TipoPrograma] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [estado] bit NOT NULL,
    [codigo] nvarchar(3) NOT NULL
);

ALTER TABLE [dbo].[TipoPrograma] ADD CONSTRAINT [PK__TipoProg__3213E83F40B07414] PRIMARY KEY CLUSTERED ([id]);
END
GO
