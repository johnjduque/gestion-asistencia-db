USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.3, SUPUESTO-C-09, O-1, O-2): usuarios que pueden resolver una revision de cancelacion.
-- Programas competentes = EstudiantePrograma del estudiante que ademas son programas vigentes del grupo (regla S1 de B2,
-- replicada de ufn_programas_grupo para no depender del orden de despliegue; la paridad la prueba C-DB-63).
-- Coordinadores activos de esos programas (excluido @idUsuarioExcluido: quien propuso); si no queda ninguno, escala a los
-- decanos activos de las facultades de esos programas (esEscalamiento = 1), tambien con la exclusion. Solo tablas base.
CREATE OR ALTER FUNCTION [dbo].[ufn_revision_cancelacion_resolutores] (@idEstudianteGrupo UNIQUEIDENTIFIER, @idUsuarioExcluido UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    WITH vigentes AS (
        SELECT DISTINCT idPrograma = pe.programa, eg.estudiante
        FROM dbo.EstudianteGrupo eg
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                             WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                            'SA Pacific Standard Time')) z
        WHERE eg.id = @idEstudianteGrupo
          AND CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
          AND (ape.fechaDesvinculacionUtc IS NULL
               OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
    ),
    competentes AS (
        SELECT idPrograma = p.id, idFacultad = p.facultad, idCoordinador = p.coordinador
        FROM vigentes v
        INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = v.estudiante AND ep.programa = v.idPrograma
        INNER JOIN dbo.Programa p ON p.id = v.idPrograma AND p.estado = 1
    ),
    coordinadores AS (
        SELECT DISTINCT idUsuario = u.id, codigoPerfil = CAST(N'COORDINADOR' AS NVARCHAR(20)), c.idPrograma, c.idFacultad, esEscalamiento = CAST(0 AS BIT)
        FROM competentes c
        INNER JOIN dbo.Coordinador co ON co.id = c.idCoordinador AND co.estado = 1
        INNER JOIN dbo.Usuario u ON u.id = co.usuario AND u.estado = 1
        WHERE (@idUsuarioExcluido IS NULL OR u.id <> @idUsuarioExcluido)
    ),
    decanos AS (
        SELECT DISTINCT idUsuario = u.id, codigoPerfil = CAST(N'DECANO' AS NVARCHAR(20)), c.idPrograma, c.idFacultad, esEscalamiento = CAST(1 AS BIT)
        FROM competentes c
        INNER JOIN dbo.Facultad f ON f.id = c.idFacultad AND f.estado = 1
        INNER JOIN dbo.Decano d ON d.id = f.decano AND d.estado = 1
        INNER JOIN dbo.Usuario u ON u.id = d.usuario AND u.estado = 1
        WHERE NOT EXISTS (SELECT 1 FROM coordinadores)
          AND (@idUsuarioExcluido IS NULL OR u.id <> @idUsuarioExcluido)
    )
    SELECT idUsuario, codigoPerfil, idPrograma, idFacultad, esEscalamiento FROM coordinadores
    UNION
    SELECT idUsuario, codigoPerfil, idPrograma, idFacultad, esEscalamiento FROM decanos
);
GO
