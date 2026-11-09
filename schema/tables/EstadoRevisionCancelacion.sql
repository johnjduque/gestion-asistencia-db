USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): estados de la revision de cancelacion por inasistencia. Los SP resuelven por banderas, no por codigo.
IF OBJECT_ID('dbo.[EstadoRevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoRevisionCancelacion (
        id                       UNIQUEIDENTIFIER NOT NULL,
        codigo                   NVARCHAR(20)     NOT NULL,
        nombre                   NVARCHAR(60)     NOT NULL,
        orden                    TINYINT          NOT NULL,
        esInicial                BIT              NOT NULL,
        requiereAccionDocente    BIT              NOT NULL,
        requiereAccionResolutor  BIT              NOT NULL,
        conservaMatricula        BIT              NOT NULL,
        cancelaMatricula         BIT              NOT NULL,
        esFinal                  BIT              NOT NULL,
        CONSTRAINT PK_EstadoRevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoRevisionCancelacion_codigo UNIQUE (codigo),
        CONSTRAINT CK_EstadoRevisionCancelacion_accion CHECK (NOT (requiereAccionDocente = 1 AND requiereAccionResolutor = 1))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstadoRevisionCancelacion') AND name = 'UX_EstadoRevisionCancelacion_esInicial')
    CREATE UNIQUE INDEX UX_EstadoRevisionCancelacion_esInicial ON dbo.EstadoRevisionCancelacion (esInicial) WHERE esInicial = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstadoRevisionCancelacion') AND name = 'UX_EstadoRevisionCancelacion_cancela')
    CREATE UNIQUE INDEX UX_EstadoRevisionCancelacion_cancela ON dbo.EstadoRevisionCancelacion (cancelaMatricula) WHERE cancelaMatricula = 1;
GO
