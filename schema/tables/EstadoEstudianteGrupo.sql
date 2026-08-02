USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[EstadoEstudianteGrupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[EstadoEstudianteGrupo] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(50) NOT NULL
);

ALTER TABLE [dbo].[EstadoEstudianteGrupo] ADD CONSTRAINT [PK__EstadoEs__3213E83FE0FCF31A] PRIMARY KEY CLUSTERED ([id]);
END
GO
