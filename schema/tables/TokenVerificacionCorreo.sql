USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: token de verificacion de correo (un solo uso). Solo se guarda el SHA-256 del token; el token en claro
-- nunca se persiste. "Activo" = no usado, no revocado y no vencido (sin columna de estado ni literales).
IF OBJECT_ID('dbo.TokenVerificacionCorreo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenVerificacionCorreo (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenVerificacionCorreo_id DEFAULT NEWID(),
        usuario            UNIQUEIDENTIFIER NOT NULL,
        tokenHash          VARBINARY(32)    NOT NULL,
        fechaEmisionUtc    DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc DATETIME2(0)     NOT NULL,
        fechaUsoUtc        DATETIME2(0)     NULL,
        fechaRevocacionUtc DATETIME2(0)     NULL,
        CONSTRAINT PK_TokenVerificacionCorreo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenVerificacionCorreo_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenVerificacionCorreo_vigencia CHECK (fechaExpiracionUtc > fechaEmisionUtc)
    );
END
GO

-- Un token activo por usuario (los literales son solo NULL, no hay valores de estado quemados).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenVerificacionCorreo_activo' AND object_id = OBJECT_ID('dbo.TokenVerificacionCorreo'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenVerificacionCorreo_activo
    ON dbo.TokenVerificacionCorreo (usuario)
    WHERE fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL;
END
GO
