USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Parametro]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Parametro] (
    [grupo] varchar(100) NOT NULL,
    [clave] varchar(100) NOT NULL,
    [valor] nvarchar(MAX) NOT NULL,
    [descripcion] nvarchar(500) NULL
);

ALTER TABLE [dbo].[Parametro] ADD CONSTRAINT [PK_Parametros] PRIMARY KEY CLUSTERED ([grupo], [clave]);
END
GO
