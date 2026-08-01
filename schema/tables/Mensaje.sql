USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Mensaje]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Mensaje] (
    [codigo] varchar(100) NOT NULL,
    [tipo] nvarchar(20) NOT NULL,
    [contenido] nvarchar(MAX) NOT NULL
);

ALTER TABLE [dbo].[Mensaje] ADD CONSTRAINT [PK_Mensajes] PRIMARY KEY CLUSTERED ([codigo], [tipo]);
END
GO
