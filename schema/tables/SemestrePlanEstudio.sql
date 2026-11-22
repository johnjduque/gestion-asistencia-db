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

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SemestrePlanEstudio') AND name = 'IX_SemestrePlanEstudio_planEstudio')
    CREATE NONCLUSTERED INDEX IX_SemestrePlanEstudio_planEstudio ON dbo.SemestrePlanEstudio (planEstudio);
GO
