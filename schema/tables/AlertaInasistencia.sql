USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2): alerta de inasistencia. Una fila por (matricula, tipo); VIGENTE | SUPERADA. fechaLecturaUtc es de C.2.
IF OBJECT_ID('dbo.[AlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertaInasistencia (
        id                          UNIQUEIDENTIFIER NOT NULL,
        estudianteGrupo             UNIQUEIDENTIFIER NOT NULL,
        tipo                        UNIQUEIDENTIFIER NOT NULL,
        estado                      UNIQUEIDENTIFIER NOT NULL,
        porcentajeCruce             DECIMAL(5,2)     NOT NULL,
        umbralCruce                 DECIMAL(5,2)     NOT NULL,
        horasFaltaCruce             DECIMAL(12,6)    NOT NULL,
        horasDictadasCruce          DECIMAL(12,6)    NOT NULL,
        fechaCruceUtc               DATETIME2(3)     NOT NULL,
        idCorrelacionCruce          UNIQUEIDENTIFIER NOT NULL,
        porcentajeUltimaEvaluacion  DECIMAL(5,2)     NOT NULL,
        fechaUltimaEvaluacionUtc    DATETIME2(3)     NOT NULL,
        fechaLecturaUtc             DATETIME2(3)     NULL,
        CONSTRAINT PK_AlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_AlertaInasistencia_porcentajes CHECK (porcentajeCruce BETWEEN 0 AND 100 AND porcentajeUltimaEvaluacion BETWEEN 0 AND 100)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.AlertaInasistencia') AND name = 'UX_AlertaInasistencia_EstudianteGrupo_Tipo')
    CREATE UNIQUE INDEX UX_AlertaInasistencia_EstudianteGrupo_Tipo ON dbo.AlertaInasistencia (estudianteGrupo, tipo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.AlertaInasistencia') AND name = 'IX_AlertaInasistencia_noLeidas')
    CREATE INDEX IX_AlertaInasistencia_noLeidas ON dbo.AlertaInasistencia (estudianteGrupo) INCLUDE (fechaLecturaUtc, fechaCruceUtc);
GO
