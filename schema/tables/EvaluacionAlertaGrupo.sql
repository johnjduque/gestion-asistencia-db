USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2, SUPUESTO-C-03, O-8): marca de agua de la evaluacion de alertas por grupo (instante de corte
-- capturado al INICIO de la evaluacion). Serializa las evaluaciones de un mismo grupo.
IF OBJECT_ID('dbo.[EvaluacionAlertaGrupo]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EvaluacionAlertaGrupo (
        grupo                UNIQUEIDENTIFIER NOT NULL,
        fechaCorteUtc        DATETIME2(3)     NOT NULL,
        idCorrelacionUltima  UNIQUEIDENTIFIER NOT NULL,
        totalEvaluaciones    INT              NOT NULL CONSTRAINT DF_EvaluacionAlertaGrupo_total DEFAULT (0),
        CONSTRAINT PK_EvaluacionAlertaGrupo PRIMARY KEY CLUSTERED (grupo)
    );
END
GO
