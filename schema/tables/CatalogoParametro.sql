USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Parametro]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[Parametro];
END
GO

IF OBJECT_ID('dbo.[CatalogoParametro]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[CatalogoParametro];
END
GO

CREATE TABLE [dbo].[CatalogoParametro] (
    [id]                UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    [grupo]             VARCHAR(100)     NOT NULL DEFAULT '',
    [clave]             VARCHAR(100)     NOT NULL DEFAULT '',
    [valor]             NVARCHAR(MAX)    NOT NULL DEFAULT '',
    [tipoDato]          VARCHAR(20)      NOT NULL DEFAULT 'STRING', -- 'STRING', 'INT', 'DECIMAL', 'BOOLEAN', 'JSON', 'DATE', 'UUID'
    [valorDefecto]      NVARCHAR(MAX)    NOT NULL DEFAULT '',
    [estaActivo]        BIT              NOT NULL DEFAULT 1,
    [fechaCreacion]     DATETIME         NOT NULL DEFAULT GETDATE(),
    [fechaModificacion] DATETIME         NOT NULL DEFAULT GETDATE(),
    CONSTRAINT [PK_CatalogoParametro] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_CatalogoParametro_Grupo_Clave] UNIQUE ([grupo], [clave])
);
GO

-- Índice optimizado para lecturas por grupo y clave de parámetro activo
CREATE NONCLUSTERED INDEX [IX_CatalogoParametro_Grupo_Clave_Activo] 
ON [dbo].[CatalogoParametro] ([grupo], [clave], [estaActivo]) 
INCLUDE ([valor], [tipoDato], [valorDefecto]);
GO
