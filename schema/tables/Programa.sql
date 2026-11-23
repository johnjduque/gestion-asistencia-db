USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Programa]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Programa] (
    [id] uniqueidentifier NOT NULL,
    [facultad] uniqueidentifier NOT NULL,
    [tipoDePrograma] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [coordinador] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Programa] ADD CONSTRAINT [PK__Programa__3213E83F41C65B8B] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- HU077: modalidad y jornada del programa (nullable, retrocompatible). Idempotente para BD existentes.
IF COL_LENGTH('dbo.Programa', 'modalidad') IS NULL
BEGIN
    ALTER TABLE [dbo].[Programa] ADD [modalidad] uniqueidentifier NULL;
END
GO

IF COL_LENGTH('dbo.Programa', 'jornada') IS NULL
BEGIN
    ALTER TABLE [dbo].[Programa] ADD [jornada] uniqueidentifier NULL;
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_facultad')
    CREATE NONCLUSTERED INDEX IX_Programa_facultad ON dbo.Programa (facultad);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_coordinador')
    CREATE NONCLUSTERED INDEX IX_Programa_coordinador ON dbo.Programa (coordinador);
GO
