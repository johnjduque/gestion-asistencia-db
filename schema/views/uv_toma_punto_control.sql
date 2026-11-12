USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §A.2): una fila por toma de asistencia con su
-- punto de control y los tramos que la rodean. Vista interna (sin GRANT): la consumen uv_asistencia_tramo y uv_toma_asistencia.
--   fechaPuntoControlUtc = apertura recortada a [inicio, fin] de la sesion (inicio si fin <= inicio).
--   Orden de los puntos: (punto, numero); el desempate por numero hace el orden determinista.
--   fechaPuntoAnteriorUtc / fechaPuntoSiguienteUtc: punto vecino o, en los bordes, inicio / fin de la sesion.
--   minutosTramoAnterior / minutosTramoSiguiente = DATEDIFF(MINUTE) del tramo (0 si fin <= inicio): la suma de los tramos de
--   una sesion es exactamente DATEDIFF(MINUTE, inicio, fin).
--   fechaAperturaSiguienteUtc: apertura de la toma siguiente por numero (= orden de apertura); la usa la regla de edicion.
--   idGrupo (BD-4, al final): grupo de la sesion; permite que un filtro por grupo llegue a Sesion antes de las ventanas.
-- Rendimiento: las ventanas se calculan dentro de un CROSS APPLY por sesion (tomas de la sesion por
-- UQ_TomaAsistencia_Sesion_Numero), no particionadas sobre toda la tabla: un filtro o un JOIN por idSesion solo lee las tomas de
-- esa sesion. Con PARTITION BY sobre la tabla completa el optimizador no empuja un JOIN correlacionado por idSesion y recalcula
-- la ventana de todas las tomas por cada fila externa.
CREATE OR ALTER VIEW [dbo].[uv_toma_punto_control]
AS
SELECT  idToma = w.idToma,
        idSesion = s.id,
        numero = w.numero,
        fechaAperturaUtc = w.fechaAperturaUtc,
        fechaCierreUtc = w.fechaCierreUtc,
        fechaHoraInicioSesion = s.fechaHoraInicio,
        fechaHoraFinSesion = s.fechaHoraFin,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        fechaPuntoControlUtc = w.punto,
        ordenPuntoControl = w.ordenPuntoControl,
        totalTomasSesion = w.totalTomasSesion,
        idTomaAnterior = w.idTomaAnterior,
        idTomaSiguiente = w.idTomaSiguiente,
        fechaPuntoAnteriorUtc = w.fechaPuntoAnteriorUtc,
        fechaPuntoSiguienteUtc = w.fechaPuntoSiguienteUtc,
        fechaAperturaSiguienteUtc = w.fechaAperturaSiguienteUtc,
        minutosTramoAnterior = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, w.fechaPuntoAnteriorUtc, w.punto), 0),
        minutosTramoSiguiente = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, w.punto, w.fechaPuntoSiguienteUtc), 0),
        esUltimoPunto = CAST(IIF(w.idTomaSiguiente IS NULL, 1, 0) AS BIT),
        idGrupo = s.grupo
FROM    dbo.Sesion s
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
CROSS APPLY (
        SELECT  p.idToma, p.numero, p.fechaAperturaUtc, p.fechaCierreUtc, p.punto,
                ordenPuntoControl = CAST(ROW_NUMBER() OVER (ORDER BY p.punto, p.numero) AS INT),
                totalTomasSesion = COUNT(*) OVER (),
                idTomaAnterior = LAG(p.idToma) OVER (ORDER BY p.punto, p.numero),
                idTomaSiguiente = LEAD(p.idToma) OVER (ORDER BY p.punto, p.numero),
                fechaPuntoAnteriorUtc = LAG(p.punto, 1, s.fechaHoraInicio) OVER (ORDER BY p.punto, p.numero),
                fechaPuntoSiguienteUtc = LEAD(p.punto, 1, s.fechaHoraFin) OVER (ORDER BY p.punto, p.numero),
                fechaAperturaSiguienteUtc = LEAD(p.fechaAperturaUtc) OVER (ORDER BY p.numero)
        FROM (
                SELECT  idToma = t.id,
                        numero = t.numero,
                        fechaAperturaUtc = t.fechaAperturaUtc,
                        fechaCierreUtc = t.fechaCierreUtc,
                        punto = CASE WHEN s.fechaHoraFin <= s.fechaHoraInicio OR t.fechaAperturaUtc <= s.fechaHoraInicio THEN s.fechaHoraInicio
                                     WHEN t.fechaAperturaUtc >= s.fechaHoraFin THEN s.fechaHoraFin
                                     ELSE CAST(t.fechaAperturaUtc AS DATETIME2(7)) END
                FROM    dbo.TomaAsistencia t
                WHERE   t.sesion = s.id
             ) p
) w;
GO
