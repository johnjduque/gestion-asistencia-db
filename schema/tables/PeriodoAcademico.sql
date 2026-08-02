USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[PeriodoAcademico]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[PeriodoAcademico] (
    [id] uniqueidentifier NOT NULL,
    [institucion] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] int NOT NULL,
    [fechaInicio] date NOT NULL,
    [fechaFin] date NOT NULL,
    [anio] int NOT NULL
);

ALTER TABLE [dbo].[PeriodoAcademico] ADD CONSTRAINT [PK__PeriodoA__3213E83F3A98B0BF] PRIMARY KEY CLUSTERED ([id]);
END
GO
