USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.EstadoNotificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoNotificacion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     VARCHAR(30)      NOT NULL,
        nombre     NVARCHAR(60)     NOT NULL,
        esTerminal BIT              NOT NULL,
        CONSTRAINT PK_EstadoNotificacion PRIMARY KEY CLUSTERED (id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_EstadoNotificacion_codigo' AND object_id = OBJECT_ID('dbo.EstadoNotificacion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_EstadoNotificacion_codigo ON dbo.EstadoNotificacion (codigo);
END
GO
