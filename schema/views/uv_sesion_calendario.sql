USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D7: una fila por sesion visible del calendario (horario semanal con fechas), sobre uv_sesion_estado (cancelacion, festivo y
-- solicitud ya resueltos alli). Excluye las sesiones cuya solicitud de sesion extraordinaria sigue pendiente o fue rechazada (solo
-- entran las sin solicitud y las aprobadas). esExtraordinaria = sesion manual (uv_sesion_manual). Instantes en UTC; el filtro por
-- fecha local institucional lo aplican los SP usp_consultar_sesiones_calendario_*.
CREATE OR ALTER VIEW [dbo].[uv_sesion_calendario]
AS
SELECT  idSesion = e.idSesion,
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        nombreGrupo = g.nombre,
        idAsignatura = g.idAsignatura,
        codigoAsignatura = a.codigo,
        nombreAsignatura = g.nombreAsignatura,
        idDocente = g.idDocente,
        nombreDocente = di.nombreCompleto,
        fechaHoraInicioUtc = e.fechaHoraInicio,
        fechaHoraFinUtc = e.fechaHoraFin,
        esExtraordinaria = CAST(IIF(m.idSesion IS NULL, 0, 1) AS BIT),
        estaCancelada = e.estaCancelada,
        motivoCancelacion = e.motivoCancelacion,
        esCancelacionAutomatica = e.esCancelacionAutomatica,
        nombreDiaFestivo = e.nombreDiaFestivo
FROM    dbo.uv_sesion_estado e
INNER JOIN dbo.uv_grupo g                    ON g.id = e.idGrupo
INNER JOIN dbo.uv_asignatura a               ON a.id = g.idAsignatura
INNER JOIN dbo.uv_docente_identidad di       ON di.id = g.idDocente
LEFT JOIN  dbo.uv_sesion_manual m            ON m.idSesion = e.idSesion
LEFT JOIN  dbo.uv_estado_solicitud_sesion es ON es.codigo = e.estadoSolicitud
WHERE   e.estadoSolicitud IS NULL OR es.esAprobada = 1;
GO
