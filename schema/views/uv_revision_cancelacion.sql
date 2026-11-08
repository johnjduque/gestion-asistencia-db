USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): una fila por revision de cancelacion con el contexto de la matricula, del docente y de la resolucion.
CREATE OR ALTER VIEW [dbo].[uv_revision_cancelacion]
AS
SELECT  id = r.id,
        idEstudianteGrupo = r.estudianteGrupo,
        idEstudiante = eg.estudiante,
        idUsuarioEstudiante = ue.id,
        nombreCompletoEstudiante = CONCAT(LTRIM(RTRIM(CONCAT(ue.primerNombre, N' ', ue.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ue.primerApellido, N' ', ue.segundoApellido)))),
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        nombreGrupo = g.nombre,
        idAsignatura = asig.id,
        nombreAsignatura = asig.nombre,
        idPeriodoAcademico = g.periodoAcademico,
        idDocenteTitular = g.docente,
        idUsuarioDocenteTitular = ud.id,
        nombreCompletoDocente = CONCAT(LTRIM(RTRIM(CONCAT(ud.primerNombre, N' ', ud.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ud.primerApellido, N' ', ud.segundoApellido)))),
        codigoEstadoMatricula = ee.codigo,
        idEstado = es.id,
        codigoEstado = es.codigo,
        nombreEstado = es.nombre,
        ordenEstado = es.orden,
        requiereAccionDocente = es.requiereAccionDocente,
        requiereAccionResolutor = es.requiereAccionResolutor,
        conservaMatricula = es.conservaMatricula,
        cancelaMatricula = es.cancelaMatricula,
        esFinal = es.esFinal,
        porcentajeCreacion = r.porcentajeCreacion,
        horasFaltaCreacion = r.horasFaltaCreacion,
        horasDictadasCreacion = r.horasDictadasCreacion,
        fechaCreacionUtc = r.fechaCreacionUtc,
        codigoDecisionDocente = r.codigoDecisionDocente,
        motivoDocente = r.motivoDocente,
        idUsuarioDecisionDocente = r.usuarioDecisionDocente,
        porcentajeDecisionDocente = r.porcentajeDecisionDocente,
        fechaDecisionDocenteUtc = r.fechaDecisionDocenteUtc,
        codigoPerfilResolutorActual = r.codigoPerfilResolutorActual,
        fechaEscalamientoUtc = r.fechaEscalamientoUtc,
        codigoDecisionResolucion = r.codigoDecisionResolucion,
        motivoResolucion = r.motivoResolucion,
        idUsuarioResolucion = r.usuarioResolucion,
        nombreCompletoResolucion = CASE WHEN ur.id IS NULL THEN NULL
                                        ELSE CONCAT(LTRIM(RTRIM(CONCAT(ur.primerNombre, N' ', ur.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ur.primerApellido, N' ', ur.segundoApellido)))) END,
        codigoPerfilResolucion = r.codigoPerfilResolucion,
        idProgramaResolucion = r.programaResolucion,
        nombreProgramaResolucion = pr.nombre,
        porcentajeResolucion = r.porcentajeResolucion,
        fechaResolucionUtc = r.fechaResolucionUtc,
        fechaActualizacionUtc = r.fechaActualizacionUtc
FROM    dbo.RevisionCancelacion r
INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Usuario ue ON ue.id = e.usuario
INNER JOIN dbo.Grupo g ON g.id = eg.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.Usuario ud ON ud.id = d.usuario
LEFT JOIN dbo.Usuario ur ON ur.id = r.usuarioResolucion
LEFT JOIN dbo.Programa pr ON pr.id = r.programaResolucion;
GO
