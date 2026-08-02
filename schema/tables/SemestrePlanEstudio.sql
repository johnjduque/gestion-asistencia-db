USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[SemestrePlanEstudio]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SemestrePlanEstudio] (
    [id] uniqueidentifier NOT NULL,
    [planEstudio] uniqueidentifier NOT NULL,
    [semestre] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[SemestrePlanEstudio] ADD CONSTRAINT [PK__Semestre__3213E83FE97FE4EC] PRIMARY KEY CLUSTERED ([id]);
END
GO
