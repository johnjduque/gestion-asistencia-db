USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2): revision de cancelacion por inasistencia. Una sola por matricula; la decide el docente titular y
-- la resuelve el coordinador del programa del estudiante o, por escalamiento, el decano (SUPUESTO-C-09).
IF OBJECT_ID('dbo.[RevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.RevisionCancelacion (
        id                           UNIQUEIDENTIFIER NOT NULL,
        estudianteGrupo              UNIQUEIDENTIFIER NOT NULL,
        estado                       UNIQUEIDENTIFIER NOT NULL,
        alertaOrigen                 UNIQUEIDENTIFIER NOT NULL,
        porcentajeCreacion           DECIMAL(5,2)     NOT NULL,
        horasFaltaCreacion           DECIMAL(12,6)    NOT NULL,
        horasDictadasCreacion        DECIMAL(12,6)    NOT NULL,
        fechaCreacionUtc             DATETIME2(3)     NOT NULL,
        idCorrelacionCreacion        UNIQUEIDENTIFIER NOT NULL,
        codigoDecisionDocente        NVARCHAR(20)     NULL,
        motivoDocente                NVARCHAR(1000)   NULL,
        usuarioDecisionDocente       UNIQUEIDENTIFIER NULL,
        porcentajeDecisionDocente    DECIMAL(5,2)     NULL,
        fechaDecisionDocenteUtc      DATETIME2(3)     NULL,
        codigoPerfilResolutorActual  NVARCHAR(20)     NULL,
        huellaResolutoresActual      VARBINARY(32)    NULL,
        fechaEscalamientoUtc         DATETIME2(3)     NULL,
        codigoDecisionResolucion     NVARCHAR(20)     NULL,
        motivoResolucion             NVARCHAR(1000)   NULL,
        usuarioResolucion            UNIQUEIDENTIFIER NULL,
        codigoPerfilResolucion       NVARCHAR(20)     NULL,
        programaResolucion           UNIQUEIDENTIFIER NULL,
        porcentajeResolucion         DECIMAL(5,2)     NULL,
        fechaResolucionUtc           DATETIME2(3)     NULL,
        estadoMatriculaAnterior      UNIQUEIDENTIFIER NULL,
        fechaActualizacionUtc        DATETIME2(3)     NOT NULL,
        CONSTRAINT PK_RevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_RevisionCancelacion_EstudianteGrupo UNIQUE (estudianteGrupo)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_estado')
    CREATE INDEX IX_RevisionCancelacion_estado ON dbo.RevisionCancelacion (estado) INCLUDE (estudianteGrupo, fechaCreacionUtc);
GO
