USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Sesion]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Sesion] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [numero] int NOT NULL,
    [codigo] nvarchar(50) NOT NULL,
    [numeroSemana] int NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [fechaHoraInicio] datetime2 NOT NULL,
    [fechaHoraFin] datetime2 NOT NULL,
    [descripcion] nvarchar(max) NULL,
    [aula] nvarchar(100) NULL,
    [tipo] nvarchar(50) NULL
);

ALTER TABLE [dbo].[Sesion] ADD CONSTRAINT [PK__Sesion__3213E83F33E5FFCB] PRIMARY KEY CLUSTERED ([id]);
END
GO
