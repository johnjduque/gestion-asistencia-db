USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2, O-14): trazabilidad de cada transicion de una revision (sin vista de consulta en C).
IF OBJECT_ID('dbo.[RevisionCancelacionHistorial]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.RevisionCancelacionHistorial (
        id                      UNIQUEIDENTIFIER NOT NULL,
        revision                UNIQUEIDENTIFIER NOT NULL,
        estadoAnterior          UNIQUEIDENTIFIER NULL,
        estadoNuevo             UNIQUEIDENTIFIER NOT NULL,
        codigoEvento            NVARCHAR(20)     NOT NULL,
        motivo                  NVARCHAR(1000)   NULL,
        usuarioActor            UNIQUEIDENTIFIER NULL,
        codigoPerfilActor       NVARCHAR(20)     NULL,
        codigoPerfilResolutor   NVARCHAR(20)     NULL,
        porcentajeInasistencia  DECIMAL(5,2)     NOT NULL,
        fechaUtc                DATETIME2(3)     NOT NULL,
        idCorrelacion           UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_RevisionCancelacionHistorial PRIMARY KEY CLUSTERED (id)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacionHistorial') AND name = 'IX_RevisionCancelacionHistorial_revision')
    CREATE INDEX IX_RevisionCancelacionHistorial_revision ON dbo.RevisionCancelacionHistorial (revision, fechaUtc);
GO
