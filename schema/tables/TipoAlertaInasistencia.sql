USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): tipo de alerta de inasistencia (ADVERTENCIA | PERDIDA).
IF OBJECT_ID('dbo.[TipoAlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TipoAlertaInasistencia (
        id                       UNIQUEIDENTIFIER NOT NULL,
        codigo                   NVARCHAR(20)     NOT NULL,
        nombre                   NVARCHAR(50)     NOT NULL,
        nivel                    TINYINT          NOT NULL,
        grupoParametroUmbral     VARCHAR(100)     NOT NULL,
        claveParametroUmbral     VARCHAR(100)     NOT NULL,
        tipoPlantillaEstudiante  VARCHAR(60)      NOT NULL,
        codigoMensajeUsuario     VARCHAR(100)     NOT NULL,
        creaRevisionCancelacion  BIT              NOT NULL,
        CONSTRAINT PK_TipoAlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TipoAlertaInasistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_TipoAlertaInasistencia_nivel UNIQUE (nivel)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TipoAlertaInasistencia') AND name = 'UX_TipoAlertaInasistencia_creaRevision')
    CREATE UNIQUE INDEX UX_TipoAlertaInasistencia_creaRevision ON dbo.TipoAlertaInasistencia (creaRevisionCancelacion) WHERE creaRevisionCancelacion = 1;
GO
