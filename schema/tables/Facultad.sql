USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Facultad]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Facultad] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [institucion] uniqueidentifier NOT NULL,
    [decano] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Facultad] ADD CONSTRAINT [PK__Facultad__3213E83FEA2EF79E] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Facultad') AND name = 'IX_Facultad_decano')
    CREATE NONCLUSTERED INDEX IX_Facultad_decano ON dbo.Facultad (decano);
GO
