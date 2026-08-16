USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Mensaje]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[Mensaje];
END
GO

IF OBJECT_ID('dbo.[CatalogoMensajeUsuario]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[CatalogoMensajeUsuario];
END
GO

CREATE TABLE [dbo].[CatalogoMensajeUsuario] (
    [id]                UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    [codigo]            VARCHAR(100)     NOT NULL DEFAULT '',
    [tipoMensaje]       VARCHAR(50)      NOT NULL DEFAULT 'BUSINESS_ERROR', -- 'SUCCESS', 'INFO', 'WARNING', 'BUSINESS_ERROR', 'SYSTEM_ERROR'
    [severidad]         VARCHAR(20)      NOT NULL DEFAULT 'MEDIO',          -- 'BAJO', 'MEDIO', 'ALTO', 'CRITICO'
    [contenido]         NVARCHAR(4000)   NOT NULL DEFAULT '',
    [estaActivo]        BIT              NOT NULL DEFAULT 1,
    [fechaCreacion]     DATETIME         NOT NULL DEFAULT GETDATE(),
    [fechaModificacion] DATETIME         NOT NULL DEFAULT GETDATE(),
    CONSTRAINT [PK_CatalogoMensajeUsuario] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_CatalogoMensajeUsuario_Codigo] UNIQUE ([codigo])
);
GO

-- Índice no agrupado para acelerar búsquedas por código y estado activo
CREATE NONCLUSTERED INDEX [IX_CatalogoMensajeUsuario_Codigo_Activo] 
ON [dbo].[CatalogoMensajeUsuario] ([codigo], [estaActivo]) 
INCLUDE ([tipoMensaje], [severidad], [contenido]);
GO
