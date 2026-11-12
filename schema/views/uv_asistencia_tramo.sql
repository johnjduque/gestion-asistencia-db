USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §A.2-§A.4): una fila por (cabecera Asistencia,
-- tramo). Una sesion con n tomas tiene n + 1 tramos: [inicio, p1] (borde, lo gobierna la toma 1), [p_k, p_k+1] (internos, los
-- gobiernan sus dos tomas) y [p_n, fin] (borde, lo gobierna la ultima). Vista interna (sin GRANT).
--   codigoRazonCausaInicio / codigoRazonCausaFin: marca del estudiante en la toma de cada extremo (en un borde, las dos son la
--   marca de la toma del borde); NULL = sin detalle.
--   codigoClasificacionTramo (conjunto cerrado), la primera que se cumpla:
--     SIN_REGISTRO si la sesion esta cancelada; AUSENTE si algun extremo es SJC; SIN_REGISTRO si algun extremo no es AN ni EX
--     (sin detalle u otra razon); EXCUSADO si algun extremo es EX; PRESENTE si los dos son AN.
--   idGrupo (BD-4, al final): grupo de la sesion, para que un filtro por grupo llegue a uv_toma_punto_control.
--   Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]). Busca la marca de la toma y la de la anterior en
--   UX_DetalleAsistencia_Asistencia_Toma, sin ventanas por estudiante.
CREATE OR ALTER VIEW [dbo].[uv_asistencia_tramo]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        ordenTramo = x.ordenTramo,
        idTomaInicio = x.idTomaInicio,
        idTomaFin = x.idTomaFin,
        fechaInicioTramoUtc = x.fechaInicioTramoUtc,
        fechaFinTramoUtc = x.fechaFinTramoUtc,
        minutosTramo = x.minutosTramo,
        codigoRazonCausaInicio = x.codigoRazonCausaInicio,
        codigoRazonCausaFin = x.codigoRazonCausaFin,
        codigoClasificacionTramo = CAST(CASE
                WHEN pc.estaSesionCancelada = 1 THEN N'SIN_REGISTRO'
                WHEN N'SJC' IN (x.codigoRazonCausaInicio, x.codigoRazonCausaFin) THEN N'AUSENTE'
                WHEN x.codigoRazonCausaInicio IS NULL OR x.codigoRazonCausaFin IS NULL
                  OR x.codigoRazonCausaInicio NOT IN (N'AN', N'EX') OR x.codigoRazonCausaFin NOT IN (N'AN', N'EX') THEN N'SIN_REGISTRO'
                WHEN N'EX' IN (x.codigoRazonCausaInicio, x.codigoRazonCausaFin) THEN N'EXCUSADO'
                ELSE N'PRESENTE' END AS NVARCHAR(12)),
        idGrupo = pc.idGrupo
FROM    dbo.Asistencia a
INNER JOIN dbo.uv_toma_punto_control pc
ON      pc.idSesion = a.sesion
LEFT JOIN dbo.DetalleAsistencia d
ON      d.asistencia = a.id AND d.toma = pc.idToma
LEFT JOIN dbo.RazonCausa rc
ON      rc.id = d.razonCausa
LEFT JOIN dbo.DetalleAsistencia dp
ON      dp.asistencia = a.id AND dp.toma = pc.idTomaAnterior
LEFT JOIN dbo.RazonCausa rcp
ON      rcp.id = dp.razonCausa
CROSS APPLY (VALUES
        -- tramo que termina en esta toma (borde inicial [inicio, p1] si no hay toma anterior)
        (pc.ordenPuntoControl - 1, pc.idTomaAnterior, pc.idToma, pc.fechaPuntoAnteriorUtc, pc.fechaPuntoControlUtc,
         pc.minutosTramoAnterior, IIF(pc.idTomaAnterior IS NULL, rc.codigo, rcp.codigo), rc.codigo),
        -- borde final [p_n, fin]: solo se conserva en la ultima toma
        (pc.ordenPuntoControl, pc.idToma, NULL, pc.fechaPuntoControlUtc, pc.fechaHoraFinSesion,
         pc.minutosTramoSiguiente, rc.codigo, rc.codigo)
     ) x (ordenTramo, idTomaInicio, idTomaFin, fechaInicioTramoUtc, fechaFinTramoUtc, minutosTramo, codigoRazonCausaInicio, codigoRazonCausaFin)
WHERE   x.ordenTramo < pc.ordenPuntoControl OR pc.esUltimoPunto = 1;
GO
