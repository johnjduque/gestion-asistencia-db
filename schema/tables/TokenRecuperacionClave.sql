USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: enlace de un solo uso para definir una contrasena nueva. Solo se guarda el SHA-256 del token del enlace; el
-- token en claro nunca se persiste. Un enlace sirve mientras no se haya usado, no se haya revocado y no haya vencido.
IF OBJECT_ID('dbo.TokenRecuperacionClave', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenRecuperacionClave (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenRecuperacionClave_id DEFAULT NEWID(),
        usuario            UNIQUEIDENTIFIER NOT NULL,
        tokenHash          VARBINARY(32)    NOT NULL,
        fechaEmisionUtc    DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc DATETIME2(0)     NOT NULL,
        fechaUsoUtc        DATETIME2(0)     NULL,
        fechaRevocacionUtc DATETIME2(0)     NULL,
        CONSTRAINT PK_TokenRecuperacionClave PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenRecuperacionClave_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenRecuperacionClave_vigencia CHECK (fechaExpiracionUtc > fechaEmisionUtc)
    );
END
GO

-- Un solo enlace pendiente por usuario: pedir otro revoca el anterior.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenRecuperacionClave_pendiente' AND object_id = OBJECT_ID('dbo.TokenRecuperacionClave'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenRecuperacionClave_pendiente
    ON dbo.TokenRecuperacionClave (usuario)
    WHERE fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL;
END
GO
