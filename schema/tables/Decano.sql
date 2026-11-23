USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Decano]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Decano] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Decano] ADD CONSTRAINT [PK_Decano] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 A.2-8 (A2-C5, F-ADM-002): estado propio del rol de decano, mismo patron que Coordinador (HU121/HU122).
-- Las filas existentes quedan activas.
IF COL_LENGTH('dbo.Decano', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[Decano] ADD [estado] bit NOT NULL CONSTRAINT [DF_Decano_estado] DEFAULT (1);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Decano') AND name = 'IX_Decano_usuario')
    CREATE NONCLUSTERED INDEX IX_Decano_usuario ON dbo.Decano (usuario);
GO
