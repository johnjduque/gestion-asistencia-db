USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.PlantillaNotificacionMarcador', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacionMarcador (
        id          UNIQUEIDENTIFIER NOT NULL,
        tipo        VARCHAR(60)      NOT NULL,
        marcador    VARCHAR(40)      NOT NULL,
        descripcion NVARCHAR(200)    NOT NULL,
        ejemplo     NVARCHAR(100)    NOT NULL,
        obligatorio BIT              NOT NULL,
        CONSTRAINT PK_PlantillaNotificacionMarcador PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacionMarcador_tipo_marcador UNIQUE (tipo, marcador),
        CONSTRAINT CK_PlantillaNotificacionMarcador_marcador CHECK (marcador LIKE '[a-zA-Z]%' AND marcador NOT LIKE '%[^a-zA-Z0-9]%')
    );
END
GO
