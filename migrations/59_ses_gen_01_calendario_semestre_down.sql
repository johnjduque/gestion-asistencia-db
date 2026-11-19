-- ============================================================================
-- MIGRACION DOWN 59: retira SES-GEN-01 (calendario de sesiones del semestre)
--   Quita Asignatura.horasSemanales (y su CHECK), los parametros PERIODO/SEMANAS_DURACION, ASIGNATURA/HORAS_SEMANALES_MAXIMO y HORARIO/*,
--   y los mensajes HOR_006..HOR_014, ASI_013, ASI_014, PER_010 y PER_011. Las horas cargadas en las asignaturas se pierden.
--   Las vistas uv_asignatura y uv_asignatura_plan_estudio se restauran aqui antes de quitar la columna. El SP
--   usp_previsualizar_horario_grupo se elimina aqui; los SP que leen o escriben horasSemanales deben restaurarse desde develop.
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 59 DOWN: retira SES-GEN-01';
GO
IF OBJECT_ID(N'dbo.usp_previsualizar_horario_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_previsualizar_horario_grupo];
GO
IF OBJECT_ID(N'dbo.uv_periodo_academico_cierre', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_periodo_academico_cierre];
GO
-- Restaurar primero la vista base y luego su consumidora para que el rollback de la columna no deje vistas invalidas.
CREATE OR ALTER VIEW [dbo].[uv_asignatura]
AS
SELECT  id = a.id,
        codigo = a.codigo,
        nombre = a.nombre,
        credito = a.credito,
        idArea = ar.id,
        nombreArea = ar.nombre,
        idComponente = co.id,
        nombreComponente = co.nombre,
        estaActivaAsignatura = a.estado,
        estaActivaTextoAsignatura = IIF(a.estado = 1, 'SI', 'NO'),
        totalPlanesActivos = (SELECT COUNT(*) FROM AsignaturaPlanEstudio x WHERE x.asignatura = a.id AND x.estaActivo = 1)
FROM    Asignatura a
INNER JOIN uv_area ar ON a.area = ar.id
INNER JOIN uv_componente co ON a.componente = co.id;
GO
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
INNER JOIN CaracterAsignaturaPlan ca ON ca.id = ape.caracter;
GO
DELETE c FROM dbo.CambioParametro c
INNER JOIN dbo.CatalogoParametro p ON p.id = c.parametro
WHERE (p.grupo = 'PERIODO' AND p.clave = 'SEMANAS_DURACION') OR (p.grupo = 'ASIGNATURA' AND p.clave = 'HORAS_SEMANALES_MAXIMO')
   OR (p.grupo = 'HORARIO' AND p.clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
    DELETE e FROM dbo.CatalogoParametroEdicion e
    INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    WHERE (p.grupo = 'PERIODO' AND p.clave = 'SEMANAS_DURACION') OR (p.grupo = 'ASIGNATURA' AND p.clave = 'HORAS_SEMANALES_MAXIMO')
       OR (p.grupo = 'HORARIO' AND p.clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
DELETE FROM dbo.CatalogoParametro
WHERE (grupo = 'PERIODO' AND clave = 'SEMANAS_DURACION') OR (grupo = 'ASIGNATURA' AND clave = 'HORAS_SEMANALES_MAXIMO')
   OR (grupo = 'HORARIO' AND clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('HOR_006', 'HOR_007', 'HOR_008', 'HOR_009', 'HOR_010', 'HOR_011', 'HOR_012', 'HOR_013', 'HOR_014', 'ASI_013', 'ASI_014', 'PER_010', 'PER_011');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('HOR_006', 'HOR_007', 'HOR_008', 'HOR_009', 'HOR_010', 'HOR_011', 'HOR_012', 'HOR_013', 'HOR_014', 'ASI_013', 'ASI_014', 'PER_010', 'PER_011');
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Asignatura_horasSemanales' AND parent_object_id = OBJECT_ID(N'dbo.Asignatura'))
    ALTER TABLE [dbo].[Asignatura] DROP CONSTRAINT [CK_Asignatura_horasSemanales];
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NOT NULL
    ALTER TABLE [dbo].[Asignatura] DROP COLUMN [horasSemanales];
GO
PRINT 'MIGRACION 59 DOWN OK';
GO
