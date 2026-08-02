USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Area]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Area] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(3) NOT NULL
);

ALTER TABLE [dbo].[Area] ADD CONSTRAINT [PK__Area__3213E83F4E11A194] PRIMARY KEY CLUSTERED ([id]);
END
GO
