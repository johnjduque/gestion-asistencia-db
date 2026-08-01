USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Estado]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Estado] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] char(1) NOT NULL
);

ALTER TABLE [dbo].[Estado] ADD CONSTRAINT [PK__Estado__3213E83F3F264112] PRIMARY KEY CLUSTERED ([id]);
END
GO
