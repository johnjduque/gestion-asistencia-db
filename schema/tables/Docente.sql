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

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Docente') AND name = 'IX_Docente_usuario')
    CREATE NONCLUSTERED INDEX IX_Docente_usuario ON dbo.Docente (usuario);
GO
