USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[TipoIdentificacion]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[TipoIdentificacion] (
    [id] uniqueidentifier NOT NULL,
    [tipoIdentificacion] nvarchar(5) NOT NULL,
    [nombre] nvarchar(50) NOT NULL
);

ALTER TABLE [dbo].[TipoIdentificacion] ADD CONSTRAINT [PK_TipoIdentificacion] PRIMARY KEY CLUSTERED ([id]);
END
GO
