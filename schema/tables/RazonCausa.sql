USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[RazonCausa]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[RazonCausa] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(5) NOT NULL
);

ALTER TABLE [dbo].[RazonCausa] ADD CONSTRAINT [PK__RazonCau__3213E83F8D311926] PRIMARY KEY CLUSTERED ([id]);
END
GO
