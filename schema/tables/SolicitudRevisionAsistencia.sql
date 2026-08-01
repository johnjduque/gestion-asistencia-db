USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[SolicitudRevisionAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SolicitudRevisionAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [fecha] date NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [justificacionSolicitud] varchar(MAX) NOT NULL,
    [justificacionRespuesta] varchar(MAX) NOT NULL
);

ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [PK__Solicitu__3213E83F81F5487B] PRIMARY KEY CLUSTERED ([id]);
END
GO
