USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[DetalleAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[DetalleAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [codigo] int NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [asistio] bit NOT NULL,
    [razonCausa] uniqueidentifier NOT NULL,
    [fechaHoraInicio] datetime2 NOT NULL,
    [fechaHoraFin] datetime2 NOT NULL
);

ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [PK__DetalleA__3213E83F60851D6A] PRIMARY KEY CLUSTERED ([id]);
END
GO
