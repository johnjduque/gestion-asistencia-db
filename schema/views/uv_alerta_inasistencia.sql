USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): una fila por alerta de inasistencia, con el contexto de la matricula y del grupo.
-- Los ids de usuario sirven al ambito dentro de los SP; los SP de consulta del estudiante no los devuelven.
CREATE OR ALTER VIEW [dbo].[uv_alerta_inasistencia]
AS
SELECT  id = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
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
        idUsuarioDocenteTitular = d.usuario,
        codigoEstadoMatricula = ee.codigo,
        idTipo = t.id,
        codigoTipo = t.codigo,
        nombreTipo = t.nombre,
        nivel = t.nivel,
        codigoMensajeUsuario = t.codigoMensajeUsuario,
        idEstado = es.id,
        codigoEstado = es.codigo,
        estaVigente = es.estaVigente,
        porcentajeCruce = a.porcentajeCruce,
        umbralCruce = a.umbralCruce,
        horasFaltaCruce = a.horasFaltaCruce,
        horasDictadasCruce = a.horasDictadasCruce,
        fechaCruceUtc = a.fechaCruceUtc,
        porcentajeUltimaEvaluacion = a.porcentajeUltimaEvaluacion,
        fechaUltimaEvaluacionUtc = a.fechaUltimaEvaluacionUtc,
        fechaLecturaUtc = a.fechaLecturaUtc,
        estaLeida = CAST(IIF(a.fechaLecturaUtc IS NULL, 0, 1) AS BIT)
FROM    dbo.AlertaInasistencia a
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Usuario ue ON ue.id = e.usuario
INNER JOIN dbo.Grupo g ON g.id = eg.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = a.tipo
INNER JOIN dbo.EstadoAlertaInasistencia es ON es.id = a.estado;
GO
