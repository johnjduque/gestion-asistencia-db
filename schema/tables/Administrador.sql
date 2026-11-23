USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Administrador]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Administrador] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL,
    [institucion] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Administrador] ADD CONSTRAINT [PK_Administrador] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Administrador') AND name = 'IX_Administrador_usuario')
    CREATE NONCLUSTERED INDEX IX_Administrador_usuario ON dbo.Administrador (usuario);
GO
