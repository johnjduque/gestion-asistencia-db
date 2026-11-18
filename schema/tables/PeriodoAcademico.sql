USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[PeriodoAcademico]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[PeriodoAcademico] (
    [id] uniqueidentifier NOT NULL,
    [institucion] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] int NOT NULL,
    [fechaInicio] date NOT NULL,
    [fechaFin] date NOT NULL,
    [anio] int NOT NULL
);

ALTER TABLE [dbo].[PeriodoAcademico] ADD CONSTRAINT [PK__PeriodoA__3213E83F3A98B0BF] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- VAL-pendientes-john PRU-15 (decision del responsable 2026-11-18): instante UTC en que usp_ejecutar_cierre_masivo_periodo cerro el
-- periodo con exito. NULL = no cerrado. Un periodo cerrado rechaza tomas, lotes y reclamos de sus sesiones (PER_008) y un segundo
-- cierre (PER_009). La migracion 49 lo llena en bases existentes desde la auditoria CIERRE_MASIVO_PERIODO de periodos ya terminados.
IF COL_LENGTH('dbo.PeriodoAcademico', 'fechaCierreUtc') IS NULL
    ALTER TABLE [dbo].[PeriodoAcademico] ADD [fechaCierreUtc] datetime2(7) NULL;
GO
