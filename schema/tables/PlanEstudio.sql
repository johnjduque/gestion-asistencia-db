USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[PlanEstudio]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[PlanEstudio] (
    [id] uniqueidentifier NOT NULL,
    [programa] uniqueidentifier NOT NULL,
    [inp] int NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[PlanEstudio] ADD CONSTRAINT [PK__PlanEstu__3213E83FD3B42CC2] PRIMARY KEY CLUSTERED ([id]);
END
GO
