USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU062/HU091/HU093: adscripcion (vinculo) del docente a un programa con estado propio. MEJORAS-SERGIO-2026-11-18 (migracion 56):
-- se retiro la columna tipoVinculacion (y la tabla TipoVinculacion).
IF OBJECT_ID('dbo.[DocentePrograma]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[DocentePrograma] (
    [id] uniqueidentifier NOT NULL,
    [docente] uniqueidentifier NOT NULL,
    [programa] uniqueidentifier NOT NULL,
    [estado] bit NOT NULL,
    [fechaVinculacionUtc] datetime2(0) NOT NULL
);

ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [PK_DocentePrograma] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [UQ_DocentePrograma_docente_programa] UNIQUE ([docente], [programa]);
END
GO

-- AUD-BD M-1 (2026-11-22): indices de apoyo para las FK de ambito y filtro (las vistas uv_auth_* y los SP de ambito filtran por estas columnas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DocentePrograma') AND name = 'IX_DocentePrograma_programa')
    CREATE NONCLUSTERED INDEX IX_DocentePrograma_programa ON dbo.DocentePrograma (programa);
GO
