USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Usuario]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Usuario] (
    [id] uniqueidentifier NOT NULL,
    [tipoIdIdentificacion] uniqueidentifier NOT NULL,
    [numeroIdentificacion] int NOT NULL,
    [primerApellido] nvarchar(50) NOT NULL,
    [segundoApellido] nvarchar(50) NOT NULL,
    [primerNombre] nvarchar(50) NOT NULL,
    [segundoNombre] nvarchar(50) NOT NULL,
    [correo] nvarchar(100) NOT NULL,
    [correoConfirmado] bit NOT NULL,
    [estado] bit NOT NULL,
    [password] nvarchar(500) NOT NULL -- Ajustado a 500 para permitir hashes de contraseña (BCrypt, Argon2, SHA-512, etc.)
);

ALTER TABLE [dbo].[Usuario] ADD CONSTRAINT [PK_Usuario] PRIMARY KEY CLUSTERED ([id]);
END
GO
