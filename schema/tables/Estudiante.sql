USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Estudiante]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Estudiante] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Estudiante] ADD CONSTRAINT [PK_Estudiante] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Estudiante') AND name = 'IX_Estudiante_usuario')
    CREATE NONCLUSTERED INDEX IX_Estudiante_usuario ON dbo.Estudiante (usuario);
GO
