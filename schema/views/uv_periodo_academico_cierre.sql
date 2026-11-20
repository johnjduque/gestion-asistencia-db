USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Proyección interna mínima para consultar el cierre UTC sin cambiar el contrato de uv_periodo_academico.
CREATE OR ALTER VIEW [dbo].[uv_periodo_academico_cierre]
AS
SELECT  id = pa.id,
        fechaCierreUtc = pa.fechaCierreUtc
FROM    dbo.PeriodoAcademico pa;
GO
