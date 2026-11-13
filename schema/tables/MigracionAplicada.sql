USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- VAL F12-12 (oleada 3): registro de migraciones aplicadas (12-factor, procesos administrativos).
-- Lo escribe solo la tarea scripts/migrar.ps1: una fila por migracion de migrations/ (archivo NN_nombre_up.sql o, en las
-- antiguas de un solo archivo, NN_nombre.sql) cuando la aplica (modo APLICADA) o cuando la registra sin ejecutarla sobre una
-- base creada con deploy_schema.ps1, que ya contiene su efecto (modo BASELINE).
--   nombre          archivo sin '_up.sql' ni '.sql' (clave unica: hay numeros de version repetidos, p. ej. 05, 06, 07, 08 y 11).
--   version         prefijo numerico del archivo (orden de aplicacion; no es unico).
--   checksumSha256  SHA-256 del archivo con CRLF normalizado a LF (mismo calculo que scripts/freeze-manifest.ps1); si el archivo
--                   cambia despues de aplicado, migrar.ps1 se detiene (deriva) en vez de reaplicarlo o ignorarlo.
-- Sin permisos para rol_asistencias_runtime: la aplicacion no migra el esquema (ddl-auto: none). Sin FK.
IF OBJECT_ID('dbo.[MigracionAplicada]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[MigracionAplicada] (
        [id]             UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_MigracionAplicada_id] DEFAULT NEWID(),
        [version]        INT              NOT NULL,
        [nombre]         VARCHAR(200)     NOT NULL,
        [archivo]        VARCHAR(260)     NOT NULL,
        [checksumSha256] CHAR(64)         NOT NULL,
        [modo]           VARCHAR(10)      NOT NULL,
        [aplicadaEnUtc]  DATETIME2(7)     NOT NULL CONSTRAINT [DF_MigracionAplicada_aplicadaEnUtc] DEFAULT SYSUTCDATETIME(),
        [aplicadaPor]    NVARCHAR(128)    NOT NULL CONSTRAINT [DF_MigracionAplicada_aplicadaPor] DEFAULT SUSER_SNAME(),
        [duracionMs]     INT              NULL,
        CONSTRAINT [PK_MigracionAplicada] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [UQ_MigracionAplicada_nombre] UNIQUE ([nombre]),
        CONSTRAINT [CK_MigracionAplicada_modo] CHECK ([modo] IN ('APLICADA', 'BASELINE')),
        CONSTRAINT [CK_MigracionAplicada_checksum] CHECK ([checksumSha256] NOT LIKE '%[^0-9a-f]%' AND LEN([checksumSha256]) = 64),
        CONSTRAINT [CK_MigracionAplicada_version] CHECK ([version] >= 0)
    );
END;
GO
