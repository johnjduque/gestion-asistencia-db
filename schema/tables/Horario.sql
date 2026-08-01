USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Horario]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Horario] (
    [id] uniqueidentifier NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [dia] uniqueidentifier NOT NULL,
    [horaInicio] time NOT NULL,
    [horaFin] time NOT NULL
);

ALTER TABLE [dbo].[Horario] ADD CONSTRAINT [PK__Horario__3213E83F084E5137] PRIMARY KEY CLUSTERED ([id]);
END
GO
