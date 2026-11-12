USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B, reclamo por toma): una fila por (cabecera
-- Asistencia, toma de su sesion), incluidas las tomas sin detalle del estudiante. La consume el backend (sesiones de la materia
-- del estudiante): el estado del estudiante en cada toma, los minutos de los tramos vecinos y si la toma se puede reclamar.
--   codigoRazonCausa             marca del estudiante en la toma (NULL = sin registro).
--   codigoEstadoTomaEstudiante   PRESENTE (AN), AUSENTE (SJC), JUSTIFICADA (EX) o SIN_REGISTRO (sin marca u otra razon).
--   idSolicitudRevision / codigoEstadoSolicitud / codigoResultadoAprobacion: la solicitud NO retirada (RECLAMO/ESTADO_RETIRADO)
--   mas reciente de esa toma (NULL si no hay); el resultado de la aprobacion es AN o EX.
--   esReclamable = marca SJC, sin solicitud no retirada de la toma, sesion no cancelada y plazo HU026B vigente
--   (ufn_calcular_fecha_limite_justificacion sobre el fin de la sesion, el mismo criterio de uv_sesion_estudiante_reclamo).
-- Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_toma_estudiante]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idToma = pc.idToma,
        numeroToma = pc.numero,
        ordenPuntoControl = pc.ordenPuntoControl,
        fechaPuntoControlUtc = pc.fechaPuntoControlUtc,
        codigoRazonCausa = rc.codigo,
        minutosTramoAnterior = pc.minutosTramoAnterior,
        minutosTramoSiguiente = pc.minutosTramoSiguiente,
        idSolicitudRevision = sol.idSolicitud,
        codigoEstadoSolicitud = sol.codigoEstado,
        codigoResultadoAprobacion = sol.codigoResultado,
        esReclamable = CAST(IIF(rc.codigo = N'SJC'
                                AND sol.idSolicitud IS NULL
                                AND pc.estaSesionCancelada = 0
                                AND SYSUTCDATETIME() < dbo.ufn_calcular_fecha_limite_justificacion(pc.fechaHoraFinSesion), 1, 0) AS BIT),
        idEstudiante = eg.estudiante,
        codigoEstadoTomaEstudiante = CAST(CASE rc.codigo WHEN N'AN' THEN N'PRESENTE'
                                                         WHEN N'SJC' THEN N'AUSENTE'
                                                         WHEN N'EX' THEN N'JUSTIFICADA'
                                                         ELSE N'SIN_REGISTRO' END AS NVARCHAR(20))
FROM    dbo.Asistencia a
INNER JOIN dbo.EstudianteGrupo eg
ON      eg.id = a.estudianteGrupo
INNER JOIN dbo.uv_toma_punto_control pc
ON      pc.idSesion = a.sesion
LEFT JOIN dbo.DetalleAsistencia d
ON      d.asistencia = a.id AND d.toma = pc.idToma
LEFT JOIN dbo.RazonCausa rc
ON      rc.id = d.razonCausa
OUTER APPLY (
        SELECT  TOP 1 idSolicitud = sra.id, codigoEstado = e.codigo, codigoResultado = rcr.codigo
        FROM    dbo.SolicitudRevisionAsistencia sra
        INNER JOIN dbo.Estado e ON e.id = sra.estado
        LEFT JOIN dbo.RazonCausa rcr ON rcr.id = sra.razonCausaResolucion
        WHERE   sra.asistencia = a.id AND sra.toma = pc.idToma
          AND   e.codigo <> CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5))
        ORDER BY sra.fecha DESC, sra.id DESC
) sol;
GO
