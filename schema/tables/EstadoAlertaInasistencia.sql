USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): estado de una alerta de inasistencia (VIGENTE | SUPERADA), resuelto por estaVigente (unica).
IF OBJECT_ID('dbo.[EstadoAlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoAlertaInasistencia (
        id          UNIQUEIDENTIFIER NOT NULL,
        codigo      NVARCHAR(20)     NOT NULL,
        nombre      NVARCHAR(50)     NOT NULL,
        estaVigente BIT              NOT NULL,
        CONSTRAINT PK_EstadoAlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoAlertaInasistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_EstadoAlertaInasistencia_estaVigente UNIQUE (estaVigente)
    );
END
GO
