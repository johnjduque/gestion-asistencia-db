USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_grupo]
AS
SELECT  g.id,
        g.idPeriodoAcademico,
        g.fechaInicioPeriodoAcademico,
        g.fechaFinPeriodoAcademico,
        g.idAsignatura,
        g.nombreAsignatura,
        g.idDocente,
        g.codigo,
        g.nombre,
        g.capacidadMaximaPermitida,
        g.estudiantesActivos,
        g.estudiantesFinalizados,
        g.estudiantesCanceladosVoluntad,
        g.estudiantesCanceladosInasistencia,
        g.cuposDisponibles,
        g.grupoEstaHablitado,
        g.grupoEstaHablitadoTexto
FROM    dbo.uv_grupo g
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            -- CULM-001 B2NM: ambito por EXISTS sobre los programas del grupo (uv_grupo_programa 1:N); sigue siendo 1 fila por grupo.
            EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Administrador adm ON adm.institucion = f.institucion
            WHERE gp.idGrupo = g.id AND adm.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Decano d ON f.decano = d.id
            WHERE gp.idGrupo = g.id AND d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Coordinador c ON pr.coordinador = c.id
            WHERE gp.idGrupo = g.id AND c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.idDocente = doc.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND eg.grupo = g.id
        )
        );
GO
