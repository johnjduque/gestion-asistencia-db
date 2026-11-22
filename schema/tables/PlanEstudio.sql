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

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PlanEstudio') AND name = 'IX_PlanEstudio_programa')
    CREATE NONCLUSTERED INDEX IX_PlanEstudio_programa ON dbo.PlanEstudio (programa);
GO
