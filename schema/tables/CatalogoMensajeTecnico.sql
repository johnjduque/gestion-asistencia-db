USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[CatalogoMensajeTecnico]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[CatalogoMensajeTecnico];
END
GO

CREATE TABLE [dbo].[CatalogoMensajeTecnico] (
    [id]                UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    [codigo]            VARCHAR(100)     NOT NULL DEFAULT '',
    [tipoMensaje]       VARCHAR(50)      NOT NULL DEFAULT 'BUSINESS_ERROR', -- 'SUCCESS', 'INFO', 'WARNING', 'BUSINESS_ERROR', 'SYSTEM_ERROR'
    [severidad]         VARCHAR(20)      NOT NULL DEFAULT 'CRITICO',        -- 'BAJO', 'MEDIO', 'ALTO', 'CRITICO'
    [contenido]         NVARCHAR(4000)   NOT NULL DEFAULT '',
    [estaActivo]        BIT              NOT NULL DEFAULT 1,
    [fechaCreacion]     DATETIME         NOT NULL DEFAULT GETDATE(),
    [fechaModificacion] DATETIME         NOT NULL DEFAULT GETDATE(),
    CONSTRAINT [PK_CatalogoMensajeTecnico] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_CatalogoMensajeTecnico_Codigo] UNIQUE ([codigo])
);
GO

-- Índice no agrupado para acelerar búsquedas por código y estado activo
CREATE NONCLUSTERED INDEX [IX_CatalogoMensajeTecnico_Codigo_Activo] 
ON [dbo].[CatalogoMensajeTecnico] ([codigo], [estaActivo]) 
INCLUDE ([tipoMensaje], [severidad], [contenido]);
GO
