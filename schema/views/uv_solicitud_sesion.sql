USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): solicitudes de sesion extraordinaria. Una fila por (sesion, programa vigente del grupo): en un grupo
-- mixto la solicitud aparece para cada programa y el SP de consulta del coordinador la colapsa a una fila por sesion.
--   pendienteAprobacion = estado en espera (esFinal = 0) y sesion no cancelada (una cancelacion del docente cierra el tramite)
--   estaCancelada       = la sesion tiene SesionCancelacion (rechazada por el coordinador o cancelada por el docente)
CREATE OR ALTER VIEW [dbo].[uv_solicitud_sesion]
AS
SELECT  idSesion = ss.sesion,
        nombreSesion = s.nombre,
        codigoSesion = s.codigo,
        idGrupo = s.grupo,
        nombreGrupo = g.nombre,
        nombreAsignatura = g.nombreAsignatura,
        idPrograma = p.id,
        nombrePrograma = p.nombre,
        idDocente = g.idDocente,
        nombreDocente = di.nombreCompleto,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estadoSolicitud = e.codigo,
        nombreEstadoSolicitud = e.nombre,
        fechaSolicitudUtc = ss.fechaSolicitudUtc,
        fechaResolucionUtc = ss.fechaResolucionUtc,
        observacion = ss.observacion,
        usuarioSolicitante = ss.usuarioSolicitante,
        pendienteAprobacion = CAST(IIF(e.esFinal = 0 AND sc.sesion IS NULL, 1, 0) AS BIT),
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.SesionSolicitud ss
INNER JOIN dbo.Sesion s                  ON s.id = ss.sesion
INNER JOIN dbo.uv_grupo g                ON g.id = s.grupo
INNER JOIN dbo.uv_docente_identidad di   ON di.id = g.idDocente
INNER JOIN dbo.EstadoSolicitudSesion e   ON e.id = ss.idEstado
LEFT JOIN  dbo.SesionCancelacion sc      ON sc.sesion = ss.sesion
CROSS APPLY dbo.ufn_programas_grupo(s.grupo) pg
INNER JOIN dbo.Programa p                ON p.id = pg.idPrograma;
GO
