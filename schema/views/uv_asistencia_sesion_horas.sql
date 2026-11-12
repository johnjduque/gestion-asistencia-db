USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-024, NB-9) + PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md
-- §A.5-§A.6; reemplaza el reparto 1/n de DEC-012): una fila por cabecera Asistencia con los minutos y horas de la sesion por
-- tramos entre puntos de control (uv_asistencia_tramo) y el estado consolidado. Las 14 columnas anteriores conservan nombre,
-- orden y tipo; las nuevas van al final.
--   minutosSesion = DATEDIFF(MINUTE, inicio, fin) (0 si fin <= inicio), el mismo criterio de ufn_horas_sesion.
--   minutosAsistidos / minutosFalta / minutosExcusa = suma de los tramos PRESENTE / AUSENTE / EXCUSADO (0 si la sesion esta
--   cancelada o no tiene tomas); minutosSinRegistro = minutosSesion - las tres.
--   horasX = CAST(minutosX AS DECIMAL(12,6)) / 60 (redondeo a 6 decimales, como ufn_horas_sesion); horasSinRegistro =
--   horasSesion - las otras tres (0 si minutosSinRegistro = 0), para que las cuatro sumen exactamente horasSesion.
--   codigoRazonCausaConsolidado: por minutos (SJC si hay falta, si no EX si hay excusa, si no AN si hay asistencia) cuando la
--   sesion no esta cancelada y tiene minutos; si eso da NULL, por marcas como antes (SJC > EX > AN).
--   esParcial = asistencia y falta en minutos. tieneFaltaSinJustaCausa = minutosFalta > 0 (por marcas si la sesion esta cancelada
--   o no tiene minutos). tomasAusentes = marcas SJC; tomasSinRegistro = tomas sin marca AN, SJC ni EX.
--   codigoEstadoSesionEstudiante (enum EstadoAsistenciaSesion): NO_DISPONIBLE si esta cancelada; PRESENTE si asistio todos los
--   minutos; AUSENTE si no asistio y tiene falta; JUSTIFICADA si solo tiene excusa; PARCIAL si asistio una parte; si no
--   NO_DISPONIBLE. Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_sesion_horas]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idGrupo = s.grupo,
        totalTomasSesion = n.totalTomas,
        tomasConRegistro = ISNULL(d.conRegistro, 0),
        horasSesion = h.horasSesion,
        horasAsistidas = hm.horasAsistidas,
        horasFalta = hm.horasFalta,
        horasExcusa = hm.horasExcusa,
        horasSinRegistro = CAST(IIF(m.minSinRegistro = 0, 0, h.horasSesion - hm.horasAsistidas - hm.horasFalta - hm.horasExcusa) AS DECIMAL(12,6)),
        codigoRazonCausaConsolidado = CAST(COALESCE(
                                        CASE WHEN x.porMinutos = 1 AND m.minFalta > 0 THEN N'SJC'
                                             WHEN x.porMinutos = 1 AND m.minExcusa > 0 THEN N'EX'
                                             WHEN x.porMinutos = 1 AND m.minAsistidos > 0 THEN N'AN' END,
                                        CASE WHEN ISNULL(d.nSJC, 0) > 0 THEN N'SJC'
                                             WHEN ISNULL(d.nEX, 0) > 0 THEN N'EX'
                                             WHEN ISNULL(d.nAN, 0) > 0 THEN N'AN' END) AS NVARCHAR(10)),
        esParcial = CAST(IIF(m.minAsistidos > 0 AND m.minFalta > 0, 1, 0) AS BIT),
        tieneFaltaSinJustaCausa = CAST(IIF(IIF(x.porMinutos = 1, m.minFalta, ISNULL(d.nFalta, 0)) > 0, 1, 0) AS BIT),
        minutosSesion = ms.minSesion,
        minutosAsistidos = m.minAsistidos,
        minutosFalta = m.minFalta,
        minutosExcusa = m.minExcusa,
        minutosSinRegistro = m.minSinRegistro,
        tomasAusentes = ISNULL(d.nSJC, 0),
        tomasSinRegistro = n.totalTomas - ISNULL(d.nAN, 0) - ISNULL(d.nSJC, 0) - ISNULL(d.nEX, 0),
        codigoEstadoSesionEstudiante = CAST(CASE
                WHEN x.cancelada = 1 THEN N'NO_DISPONIBLE'
                WHEN ms.minSesion > 0 AND m.minAsistidos = ms.minSesion THEN N'PRESENTE'
                WHEN m.minAsistidos = 0 AND m.minFalta > 0 THEN N'AUSENTE'
                WHEN m.minAsistidos = 0 AND m.minExcusa > 0 THEN N'JUSTIFICADA'
                WHEN m.minAsistidos > 0 THEN N'PARCIAL'
                ELSE N'NO_DISPONIBLE' END AS NVARCHAR(20))
FROM    dbo.Asistencia a
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT minSesion = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin), 0)) ms
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = a.sesion) n
CROSS APPLY (SELECT cancelada = CAST(IIF(EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = a.sesion), 1, 0) AS BIT)) c
CROSS APPLY (SELECT cancelada = c.cancelada,
                    reparte = CAST(IIF(n.totalTomas > 0 AND c.cancelada = 0, 1, 0) AS BIT),
                    porMinutos = CAST(IIF(c.cancelada = 0 AND ms.minSesion > 0, 1, 0) AS BIT)) x
-- Minutos por clasificacion: JOIN a un agregado por idAsistencia (no OUTER APPLY) para que el optimizador pueda resolver por
-- conjuntos las lecturas masivas (resumenes, KPIs); un filtro por idAsistencia, idEstudianteGrupo o idSesion se empuja por
-- las columnas de agrupacion (idEstudianteGrupo e idSesion son redundantes con idAsistencia: solo sirven para eso). PC BD-4: idGrupo
-- (grupo de la sesion) tambien es redundante; con el, un filtro por grupo (directo o el de uv_resumen_asistencia_estudiante_grupo)
-- llega a Sesion antes de calcular los tramos y solo se leen las cabeceras de ese grupo.
LEFT JOIN (
        SELECT  tr.idAsistencia, tr.idEstudianteGrupo, tr.idSesion, tr.idGrupo,
                minAsistidos = SUM(IIF(tr.codigoClasificacionTramo = N'PRESENTE', tr.minutosTramo, 0)),
                minFalta = SUM(IIF(tr.codigoClasificacionTramo = N'AUSENTE', tr.minutosTramo, 0)),
                minExcusa = SUM(IIF(tr.codigoClasificacionTramo = N'EXCUSADO', tr.minutosTramo, 0))
        FROM    dbo.uv_asistencia_tramo tr
        GROUP BY tr.idAsistencia, tr.idEstudianteGrupo, tr.idSesion, tr.idGrupo
) tr
ON      tr.idAsistencia = a.id AND tr.idEstudianteGrupo = a.estudianteGrupo AND tr.idSesion = a.sesion AND tr.idGrupo = s.grupo AND x.reparte = 1
OUTER APPLY (
        SELECT  conRegistro = COUNT(1),
                nAN = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                nFalta = SUM(IIF(rc.codigo = N'SJC' AND da.asistio = 0, 1, 0)),
                nSJC = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                nEX = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.asistencia = a.id
) d
CROSS APPLY (SELECT minAsistidos = ISNULL(tr.minAsistidos, 0),
                    minFalta = ISNULL(tr.minFalta, 0),
                    minExcusa = ISNULL(tr.minExcusa, 0),
                    minSinRegistro = ms.minSesion - ISNULL(tr.minAsistidos, 0) - ISNULL(tr.minFalta, 0) - ISNULL(tr.minExcusa, 0)) m
CROSS APPLY (SELECT horasAsistidas = CAST(CAST(m.minAsistidos AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6)),
                    horasFalta = CAST(CAST(m.minFalta AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6)),
                    horasExcusa = CAST(CAST(m.minExcusa AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6))) hm;
GO
