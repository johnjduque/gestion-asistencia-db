USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1): una fila por (matricula activa, toma reclamable) de sesiones ya avisadas por correo.
-- Es uv_asistencia_toma_estudiante con esReclamable = 1 (marca SJC, sin solicitud no retirada, sesion no cancelada, plazo vigente) unida a
-- AvisoFaltaSesion (la sesion ya tiene su aviso) y a la matricula en estado MATRICULA/ESTADO_INSCRITA. La lista se vacia sola cuando el
-- estudiante radica el reclamo, vence el plazo o el docente corrige la marca. fechaLimiteReclamoUtc usa el mismo criterio de esReclamable
-- (ufn_calcular_fecha_limite_justificacion sobre el fin de la sesion). idUsuarioEstudiante sirve al ambito dentro del SP de consulta.
CREATE OR ALTER VIEW [dbo].[uv_falta_reclamable_estudiante]
AS
SELECT  idUsuarioEstudiante = e.usuario,
        idEstudianteGrupo = t.idEstudianteGrupo,
        idGrupo = g.id,
        nombreGrupo = g.nombre,
        idAsignatura = asig.id,
        nombreAsignatura = asig.nombre,
        idSesion = s.id,
        numeroSesion = s.numero,
        fechaHoraInicioUtc = s.fechaHoraInicio,
        fechaHoraFinUtc = s.fechaHoraFin,
        idToma = t.idToma,
        numeroToma = t.numeroToma,
        fechaPuntoControlUtc = t.fechaPuntoControlUtc,
        fechaLimiteReclamoUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)
FROM    dbo.uv_asistencia_toma_estudiante t
INNER JOIN dbo.AvisoFaltaSesion av ON av.sesion = t.idSesion
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = t.idEstudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Sesion s ON s.id = t.idSesion
INNER JOIN dbo.Grupo g ON g.id = s.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
WHERE   t.esReclamable = 1
  AND   ee.codigo = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
GO
