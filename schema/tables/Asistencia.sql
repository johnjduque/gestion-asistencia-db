USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Asistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Asistencia] (
    [id] uniqueidentifier NOT NULL,
    [estudianteGrupo] uniqueidentifier NOT NULL,
    [sesion] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Asistencia] ADD CONSTRAINT [PK__Asistenc__3213E83F4635E5C7] PRIMARY KEY CLUSTERED ([id]);
END
GO
