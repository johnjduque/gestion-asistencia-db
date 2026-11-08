USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.6): programas vigentes de un grupo segun la tabla puente (regla S1 de vigencia del vinculo).
-- Solo lee tablas base (las funciones se despliegan antes que las vistas). Por programa elige un unico plan:
-- activo primero, mayor inp, menor id.
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_grupo] (@idGrupo UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  x.idPrograma, x.idPlanEstudio, x.inpPlanEstudio
    FROM (
        SELECT  idPrograma = pe.programa,
                idPlanEstudio = pe.id,
                inpPlanEstudio = pe.inp,
                rn = ROW_NUMBER() OVER (PARTITION BY pe.programa ORDER BY pe.estado DESC, pe.inp DESC, pe.id ASC)
        FROM    dbo.Grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                             WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                            'SA Pacific Standard Time')) z
        WHERE   g.id = @idGrupo
          AND   CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
          AND   (ape.fechaDesvinculacionUtc IS NULL
                 OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
    ) x
    WHERE x.rn = 1
);
GO
