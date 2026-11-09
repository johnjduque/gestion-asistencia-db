USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- CULM-001 B2NM (DEC-019): tabla puente N:M entre Asignatura y SemestrePlanEstudio, con caracter y vigencia (S1).
IF OBJECT_ID('dbo.AsignaturaPlanEstudio', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AsignaturaPlanEstudio (
        id                      UNIQUEIDENTIFIER NOT NULL,
        asignatura              UNIQUEIDENTIFIER NOT NULL,
        semestrePlanEstudio     UNIQUEIDENTIFIER NOT NULL,
        caracter                UNIQUEIDENTIFIER NOT NULL,
        estaActivo              BIT              NOT NULL CONSTRAINT DF_AsignaturaPlanEstudio_estaActivo DEFAULT (1),
        fechaVinculacionUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_AsignaturaPlanEstudio_fechaVinculacionUtc DEFAULT (SYSUTCDATETIME()),
        fechaDesvinculacionUtc  DATETIME2(3)     NULL,
        CONSTRAINT PK_AsignaturaPlanEstudio PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_AsignaturaPlanEstudio_asignatura_semestre UNIQUE (asignatura, semestrePlanEstudio),
        CONSTRAINT CK_AsignaturaPlanEstudio_vigencia CHECK (
               (estaActivo = 1 AND fechaDesvinculacionUtc IS NULL)
            OR (estaActivo = 0 AND fechaDesvinculacionUtc IS NOT NULL AND fechaDesvinculacionUtc >= fechaVinculacionUtc))
    );
    CREATE INDEX IX_AsignaturaPlanEstudio_semestre
        ON dbo.AsignaturaPlanEstudio (semestrePlanEstudio) INCLUDE (asignatura, caracter, estaActivo);
END
