USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT 2.5): 1 fila por vinculo (asignatura, semestre de un plan), con caracter y programa.
CREATE OR ALTER VIEW [dbo].[uv_asignatura_plan_estudio]
AS
SELECT  idAsignaturaPlanEstudio = ape.id,
        idAsignatura = a.id,
        codigoAsignatura = a.codigo,
        nombreAsignatura = a.nombre,
        credito = a.credito,
        idArea = a.idArea,
        nombreArea = a.nombreArea,
        idComponente = a.idComponente,
        codigoComponente = co.codigo,
        nombreComponente = a.nombreComponente,
        estaActivaAsignatura = a.estaActivaAsignatura,
        idSemestrePlanEstudio = sp.id,
        idSemestre = sp.idSemestre,
        numeroSemestre = sp.numeroSemestre,
        codigoSemestre = s.codigo,
        idPlanEstudio = pe.id,
        inpPlanEstudio = pe.inp,
        estaActivoPlan = pe.estaActivoPlanEstudio,
        idPrograma = pr.id,
        nombrePrograma = pr.nombrePrograma,
        idFacultad = pr.idFacultad,
        idInstitucion = pr.idInstitucion,
        idCaracter = ca.id,
        codigoCaracter = ca.codigo,
        nombreCaracter = ca.nombre,
        ordenCaracter = ca.orden,
        estaActivoVinculo = ape.estaActivo,
        fechaVinculacionUtc = ape.fechaVinculacionUtc,
        fechaDesvinculacionUtc = ape.fechaDesvinculacionUtc,
        totalProgramasActivos = (SELECT COUNT(DISTINCT p2.programa)
                                 FROM AsignaturaPlanEstudio x
                                 INNER JOIN SemestrePlanEstudio sx ON sx.id = x.semestrePlanEstudio
                                 INNER JOIN PlanEstudio p2 ON p2.id = sx.planEstudio
                                 WHERE x.asignatura = a.id AND x.estaActivo = 1)
FROM    AsignaturaPlanEstudio ape
INNER JOIN uv_asignatura a ON a.id = ape.asignatura
INNER JOIN Componente co ON co.id = a.idComponente
INNER JOIN uv_semestre_plan_estudio sp ON sp.id = ape.semestrePlanEstudio
INNER JOIN uv_semestre s ON s.id = sp.idSemestre
INNER JOIN uv_plan_estudio pe ON pe.id = sp.idPlanEstudio
INNER JOIN uv_programa pr ON pr.id = pe.idPrograma
INNER JOIN CaracterAsignaturaPlan ca ON ca.id = ape.caracter
GO
