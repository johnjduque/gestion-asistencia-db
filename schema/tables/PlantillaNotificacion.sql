USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.PlantillaNotificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacion (
        id        UNIQUEIDENTIFIER NOT NULL,
        tipo      VARCHAR(60)      NOT NULL,
        idioma    CHAR(2)          NOT NULL CONSTRAINT DF_PlantillaNotificacion_idioma DEFAULT 'es',
        version   INT              NOT NULL,
        asunto    NVARCHAR(200)    NOT NULL,
        cuerpo    NVARCHAR(4000)   NOT NULL,
        activa    BIT              NOT NULL,
        creadoPor UNIQUEIDENTIFIER NULL,
        creadoEn  DATETIME2(3)     NOT NULL,
        CONSTRAINT PK_PlantillaNotificacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacion_tipo_idioma_version UNIQUE (tipo, idioma, version),
        CONSTRAINT CK_PlantillaNotificacion_version CHECK (version >= 1),
        CONSTRAINT CK_PlantillaNotificacion_tipo CHECK (LEN(TRIM(tipo)) BETWEEN 3 AND 60 AND tipo NOT LIKE '%[^A-Z0-9_]%')
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_PlantillaNotificacion_activa' AND object_id = OBJECT_ID('dbo.PlantillaNotificacion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PlantillaNotificacion_activa
    ON dbo.PlantillaNotificacion (tipo, idioma)
    WHERE activa = 1;
END
GO
