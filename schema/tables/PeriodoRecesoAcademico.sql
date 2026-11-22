USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081 (2026-11-21): dia de receso academico de un periodo (un dia completo sin clase para toda la institucion del periodo).
-- Un dia por registro: fecha + motivo libre. El borrado es logico (estaActivo = 0) y solo se permite mientras el dia no haya
-- cancelado ninguna sesion (usp_retirar_receso_academico). La unicidad (periodo, fecha) rige solo para los activos, de modo que un
-- dia retirado puede volver a registrarse. Las sesiones canceladas por el dia se enlazan en dbo.SesionCancelacion.recesoAcademico.
IF OBJECT_ID('dbo.[PeriodoRecesoAcademico]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PeriodoRecesoAcademico (
        id                 UNIQUEIDENTIFIER NOT NULL,
        periodoAcademico   UNIQUEIDENTIFIER NOT NULL,
        fecha              DATE             NOT NULL,
        motivo             NVARCHAR(200)    NOT NULL,
        estaActivo         BIT              NOT NULL CONSTRAINT DF_PeriodoRecesoAcademico_estaActivo DEFAULT 1,
        fechaCreacionUtc   DATETIME2(0)     NOT NULL CONSTRAINT DF_PeriodoRecesoAcademico_fecha DEFAULT SYSUTCDATETIME(),
        usuarioCreador     UNIQUEIDENTIFIER NOT NULL,
        idCorrelacion      UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_PeriodoRecesoAcademico PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_PeriodoRecesoAcademico_motivo CHECK (LEN(LTRIM(RTRIM(motivo))) > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PeriodoRecesoAcademico') AND name = 'UX_PeriodoRecesoAcademico_periodo_fecha')
    CREATE UNIQUE NONCLUSTERED INDEX UX_PeriodoRecesoAcademico_periodo_fecha
    ON dbo.PeriodoRecesoAcademico (periodoAcademico, fecha) WHERE estaActivo = 1;
GO
