USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Semestre]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Semestre] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [numero] int NOT NULL,
    [codigo] nvarchar(50) NOT NULL
);

ALTER TABLE [dbo].[Semestre] ADD CONSTRAINT [PK__Semestre__3213E83FE678E4E1] PRIMARY KEY CLUSTERED ([id]);
END
GO
