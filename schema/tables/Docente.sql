USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Docente]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Docente] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Docente] ADD CONSTRAINT [PK__Docente__3213E83FEE57B097] PRIMARY KEY CLUSTERED ([id]);
END
GO
