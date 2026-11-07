USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.6, R6/R10): matriculas de un grupo visibles para un ejecutor.
--   * Docente titular del grupo y administrador de la institucion del grupo: todas las matriculas (R10).
--   * Coordinador y decano: matriculas cuyo estudiante tiene EstudiantePrograma en (programas del grupo ∩ ambito del ejecutor) (R6).
-- Lee solo tablas base y no llama a otras ufn_* (el orden de despliegue es alfabetico).
CREATE OR ALTER FUNCTION [dbo].[ufn_estudiantes_grupo_visibles] (@idGrupo UNIQUEIDENTIFIER, @idUsuarioEjecutor UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idEstudianteGrupo = eg.id, idEstudiante = eg.estudiante
    FROM    dbo.EstudianteGrupo eg
    WHERE   eg.grupo = @idGrupo
      AND (
            EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente doc ON doc.id = g.docente
                    WHERE g.id = @idGrupo AND doc.usuario = @idUsuarioEjecutor)
         OR EXISTS (SELECT 1
                    FROM dbo.Grupo g
                    INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                    INNER JOIN dbo.Administrador adm ON adm.institucion = pa.institucion
                    WHERE g.id = @idGrupo AND adm.usuario = @idUsuarioEjecutor)
         OR EXISTS (SELECT 1
                    FROM dbo.EstudiantePrograma ep
                    INNER JOIN dbo.Grupo g ON g.id = @idGrupo
                    INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                    INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio AND pe.programa = ep.programa
                    CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                                         WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                                        'SA Pacific Standard Time')) z
                    WHERE ep.estudiante = eg.estudiante
                      AND CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
                      AND (ape.fechaDesvinculacionUtc IS NULL
                           OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
                      AND (EXISTS (SELECT 1 FROM dbo.Programa p INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                                   WHERE p.id = ep.programa AND c.usuario = @idUsuarioEjecutor)
                           OR EXISTS (SELECT 1 FROM dbo.Programa p INNER JOIN dbo.Facultad f ON f.id = p.facultad
                                      INNER JOIN dbo.Decano d ON d.id = f.decano
                                      WHERE p.id = ep.programa AND d.usuario = @idUsuarioEjecutor)))
      )
);
GO
