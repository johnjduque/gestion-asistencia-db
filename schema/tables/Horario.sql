USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Horario]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Horario] (
    [id] uniqueidentifier NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [dia] uniqueidentifier NOT NULL,
    [horaInicio] time NOT NULL,
    [horaFin] time NOT NULL
);

ALTER TABLE [dbo].[Horario] ADD CONSTRAINT [PK__Horario__3213E83F084E5137] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_grupo')
    CREATE NONCLUSTERED INDEX IX_Horario_grupo ON dbo.Horario (grupo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_dia')
    CREATE NONCLUSTERED INDEX IX_Horario_dia ON dbo.Horario (dia);
GO
