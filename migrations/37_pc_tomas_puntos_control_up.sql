-- ============================================================================
-- MIGRACION UP 37: PC - tomas de asistencia como puntos de control (docs/work-items/PC-puntos-control-tomas)
--   BD-1 calculo por tramos: vistas NUEVAS uv_toma_punto_control y uv_asistencia_tramo; uv_asistencia_sesion_horas (minutos por tramo,
--        columnas al final), uv_toma_asistencia (punto de control al final) y uv_detalle_asistencia_v2 (comentario: horasToma obsoleto).
--   BD-2 ciclo de vida de la toma: TOM_012 en usp_registrar_asistencias_toma (una toma cerrada se corrige hasta que se abre la siguiente),
--        columnas nuevas de usp_consultar_tomas_sesion, SP NUEVO usp_consultar_resumen_tomas_sesion, tope de tomas 20 (solo si sigue en 4)
--        y modo MANUAL que marca SJC al cerrar (las tomas MANUAL ya cerradas no se rellenan).
--   BD-3 reclamo por toma: columnas toma y razonCausaResolucion en SolicitudRevisionAsistencia (FK e indice), vista NUEVA
--        uv_asistencia_toma_estudiante, uv_solicitud_revision_asistencia (columnas al final), @idToma en usp_internal_radicar_solicitud_revision,
--        SP NUEVO usp_radicar_solicitud_revision_asistencia_v4, @codigoResultadoAprobacion en usp_resolver_solicitud_revision_asistencia y
--        columnas nuevas en las consultas de reclamos del estudiante y del detalle del docente; mensajes TOM_012 y REV_026..REV_029.
-- No reescribe datos de asistencia: la regla aplica por vistas a todas las sesiones. Idempotente.
-- Down: 37_pc_tomas_puntos_control_down.sql (con reclamos por toma exige CONFIRMAR_RETIRO_RECLAMO_TOMA = 1).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 37 UP: PC tomas de asistencia como puntos de control';
GO
-- ---- schema/tables/SolicitudRevisionAsistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[SolicitudRevisionAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SolicitudRevisionAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [fecha] date NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [justificacionSolicitud] varchar(MAX) NOT NULL,
    [justificacionRespuesta] varchar(MAX) NOT NULL
);

ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [PK__Solicitu__3213E83F81F5487B] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 D.2 (TD-060, HU014/HU015): categoria con la que el estudiante justifico el reclamo (FK a CategoriaJustificacion en
-- zz_foreign_keys.sql). Sin backfill: los reclamos anteriores quedan con NULL (el formulario anterior no la persistia).
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [categoriaJustificacion] uniqueidentifier NULL;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B): reclamo por toma.
--   toma                  toma reclamada (FK a TomaAsistencia); NULL = reclamo de la sesion completa (v2/v3, legado).
--   razonCausaResolucion  resultado de una aprobacion (FK a RazonCausa): AN = estuvo presente, EX = ausencia justificada;
--                         NULL mientras no se apruebe y en los reclamos aprobados antes de PC.
-- FKs e indice (asistencia, toma) en zz_foreign_keys.sql. Sin backfill.
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'toma') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [toma] uniqueidentifier NULL;
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'razonCausaResolucion') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [razonCausaResolucion] uniqueidentifier NULL;
GO
GO
-- ---- schema/tables/zz_foreign_keys.sql (solo la seccion PC)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- PC (puntos de control): SolicitudRevisionAsistencia -> TomaAsistencia (toma reclamada) y -> RazonCausa (resultado de la
-- aprobacion), sin ON DELETE CASCADE, e indice (asistencia, toma) INCLUDE (estado) para validar "un reclamo no retirado por toma".
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'toma') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_TomaAsistencia')
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [FK_SolicitudRevisionAsistencia_TomaAsistencia]
    FOREIGN KEY ([toma]) REFERENCES [dbo].[TomaAsistencia] ([id]);
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'razonCausaResolucion') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_RazonCausaResolucion')
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [FK_SolicitudRevisionAsistencia_RazonCausaResolucion]
    FOREIGN KEY ([razonCausaResolucion]) REFERENCES [dbo].[RazonCausa] ([id]);
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'toma') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_Asistencia_Toma')
    CREATE NONCLUSTERED INDEX [IX_SolicitudRevisionAsistencia_Asistencia_Toma] ON [dbo].[SolicitudRevisionAsistencia] ([asistencia], [toma]) INCLUDE ([estado]);
GO
-- ---- schema/views/uv_toma_punto_control.sql
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
GO
-- ---- schema/views/uv_asistencia_tramo.sql
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
GO
-- ---- schema/views/uv_asistencia_sesion_horas.sql
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
GO
-- ---- schema/views/uv_toma_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5): una fila por toma de asistencia con su modo, estado, ventana de la sesion y conteos.
--   horasSesion = ufn_horas_sesion(inicio, fin); totalTomasSesion = tomas de la sesion; horasToma = horasSesion /
--   totalTomasSesion (0 si la sesion esta cancelada). Conteos de la toma por RazonCausa (literales de catalogo cerrado,
--   [SUPUESTO-B-03]): totalPresentes AN, totalAusentes SJC, totalExcusas EX. tieneQrActivo = token sin fechaCierreUtc.
-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §A.2): agrega al final el punto de control de la
--   toma (uv_toma_punto_control): fechaPuntoControlUtc, ordenPuntoControl, minutosTramoAnterior, minutosTramoSiguiente y
--   fechaAperturaSiguienteUtc. horasToma (1/n) queda OBSOLETO (expand & contract): se conserva por compatibilidad y ningun
--   calculo de horas debe usarlo; las horas salen de uv_asistencia_sesion_horas.
CREATE OR ALTER VIEW [dbo].[uv_toma_asistencia]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numero = t.numero,
        idModo = m.id,
        codigoModo = m.codigo,
        nombreModo = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar,
        idEstado = e.id,
        codigoEstado = e.codigo,
        nombreEstado = e.nombre,
        estaAbierta = e.estaAbierta,
        esImplicita = t.esImplicita,
        idDocenteApertura = t.docenteApertura,
        fechaAperturaUtc = t.fechaAperturaUtc,
        fechaCierreUtc = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        fechaHoraInicioSesion = s.fechaHoraInicio,
        fechaHoraFinSesion = s.fechaHoraFin,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        horasSesion = h.horasSesion,
        totalTomasSesion = n.totalTomas,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, h.horasSesion / n.totalTomas, 0) AS DECIMAL(12,6)),
        totalRegistros = ISNULL(d.totalRegistros, 0),
        totalPresentes = ISNULL(d.totalPresentes, 0),
        totalAusentes = ISNULL(d.totalAusentes, 0),
        totalExcusas = ISNULL(d.totalExcusas, 0),
        tieneQrActivo = CAST(IIF(EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WHERE tk.toma = t.id AND tk.fechaCierreUtc IS NULL), 1, 0) AS BIT),
        fechaPuntoControlUtc = pc.fechaPuntoControlUtc,
        ordenPuntoControl = pc.ordenPuntoControl,
        minutosTramoAnterior = pc.minutosTramoAnterior,
        minutosTramoSiguiente = pc.minutosTramoSiguiente,
        fechaAperturaSiguienteUtc = pc.fechaAperturaSiguienteUtc
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.EstadoTomaAsistencia e
ON      e.id = t.estado
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = t.sesion
INNER JOIN dbo.uv_toma_punto_control pc
ON      pc.idToma = t.id AND pc.idSesion = t.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n
OUTER APPLY (
        SELECT  totalRegistros = COUNT(1),
                totalPresentes = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                totalAusentes = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                totalExcusas = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.toma = t.id
) d;
GO
GO
-- ---- schema/views/uv_detalle_asistencia_v2.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-011, DEC-012): detalle de asistencia por toma. Mismas columnas de uv_detalle_asistencia
-- (congelada, intacta) + la toma, la sesion, la matricula, el modo, las horas que vale la toma (0 si la sesion esta
-- cancelada), quien registro (registradoPorEstudiante) y cuando (fechaRegistroUtc).
-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md): horasToma (1/n) queda OBSOLETO (expand &
-- contract); se conserva por compatibilidad y ningun calculo de horas debe usarlo (ver uv_asistencia_sesion_horas).
CREATE OR ALTER VIEW [dbo].[uv_detalle_asistencia_v2]
AS
SELECT  id = da.id,
        codigo = da.codigo,
        idAsistencia = a.id,
        asistio = da.asistio,
        idRazonCausa = rc.id,
        nombreRazonCausa = rc.nombre,
        codigoRazonCausa = rc.codigo,
        fechaHoraInicio = da.fechaHoraInicio,
        fechaHoraFin = da.fechaHoraFin,
        idToma = t.id,
        numeroToma = t.numero,
        idSesion = a.sesion,
        idEstudianteGrupo = a.estudianteGrupo,
        idModoToma = m.id,
        codigoModoToma = m.codigo,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / n.totalTomas, 0) AS DECIMAL(12,6)),
        registradoPorEstudiante = da.registradoPorEstudiante,
        fechaRegistroUtc = da.fechaRegistroUtc,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.DetalleAsistencia da
INNER JOIN dbo.Asistencia a
ON      a.id = da.asistencia
INNER JOIN dbo.uv_razon_causa rc
ON      rc.id = da.razonCausa
INNER JOIN dbo.TomaAsistencia t
ON      t.id = da.toma
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = a.sesion
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n;
GO
GO
-- ---- schema/views/uv_solicitud_revision_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_solicitud_revision_asistencia]
AS
SELECT		id = sr.id,
			nombre = sr.nombre,
			idAsistencia = asi.id,
			fecha = sr.fecha,
			idEstado = est.id,
			nombreEstado = est.nombre,
			justificacionSolicitud = sr.justificacionSolicitud,
			justificacionRespuesta = sr.justificacionRespuesta,
			-- CULM-001 D.2 (TD-060, HU015): categoria persistida y total de soportes vinculados (columnas al final)
			idCategoriaJustificacion = cat.id,
			codigoCategoria = cat.codigo,
			nombreCategoria = cat.nombre,
			totalSoportes = (SELECT COUNT(*) FROM uv_soporte_reclamo sop WHERE sop.idSolicitud = sr.id),
			-- PC (puntos de control, reclamo por toma; columnas al final): toma reclamada (NULL = reclamo de la sesion) y resultado
			-- de la aprobacion (AN = estuvo presente, EX = ausencia justificada; NULL si no se aprobo o se aprobo antes de PC)
			idToma = sr.toma,
			numeroToma = tom.numero,
			codigoResultadoAprobacion = rcr.codigo

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
LEFT JOIN	CategoriaJustificacion cat
ON			sr.categoriaJustificacion = cat.id
LEFT JOIN	TomaAsistencia tom
ON			sr.toma = tom.id
LEFT JOIN	RazonCausa rcr
ON			sr.razonCausaResolucion = rcr.id
GO
GO
-- ---- schema/views/uv_resumen_asistencia_estudiante_grupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
-- CULM-001 B2NM: sin idPrograma (1 fila por matricula); el resumen por programa es uv_resumen_asistencia_estudiante_programa_grupo.
-- PC BD-4 (rendimiento, sin cambio de resultado): las horas se agrupan tambien por idGrupo (grupo de la sesion = grupo de la
-- matricula) y se unen por (idEstudianteGrupo, idGrupo); asi un filtro por grupo llega a uv_asistencia_sesion_horas antes de
-- calcular los tramos de todas las cabeceras.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPeriodoAcademico = g.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo, h.idGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo, h.idGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id AND hs.idGrupo = eg.idGrupo
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO
GO
-- ---- schema/views/uv_asistencia_toma_estudiante.sql
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
GO
-- ---- schema/stored-procedures/usp_registrar_asistencias_toma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_asistencias_toma (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013; PC puntos de control)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, totalRegistros
-- (NULL si estadoResultado = 0).
--
-- Lote del docente titular sobre UNA toma, siempre dentro de la ventana [inicio - TOLERANCIA, fin + MARGEN) (SES_007..010).
-- PC (puntos de control, reemplaza [SUPUESTO-B-08]): la toma abierta se edita; una toma cerrada solo se corrige mientras no
-- exista una toma posterior (TOM_012 en cuanto se abre la siguiente); la ultima, hasta el fin de la ventana. Despues, la
-- correccion es por reclamo del estudiante. @asistenciaJSON = [{"idEstudiante":"uuid","estado":"AN|SJC|EX"}] con las mismas
-- reglas del lote congelado: ATT_001 (no es arreglo o claves distintas de idEstudiante/estado), ATT_002 (vacio), GEN_002
-- (idEstudiante nulo o invalido), RC_001 (estado fuera de AN/SJC/EX), ATT_003 (duplicado), EST_004 (sin matricula A).
-- Todo se valida antes de escribir; el lote es atomico; la ventana se revalida al confirmar. Exito TOM_010.
-- Bloqueos: Sesion (ventana) -> TomaAsistencia -> EstudianteGrupo -> Asistencia -> DetalleAsistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencias_toma]
(
    @idToma            UNIQUEIDENTIFIER,
    @asistenciaJSON    NVARCHAR(MAX),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @huboEscritura          BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoActiva      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @totalEstudiantes  INT = 0;
    DECLARE @iterador          INT = 1;
    DECLARE @idEstudianteActual UNIQUEIDENTIFIER;
    DECLARE @estadoActual      NVARCHAR(200);
    DECLARE @idEstudianteInvalido UNIQUEIDENTIFIER;
    DECLARE @secuenciaInvalida INT;
    DECLARE @estadoInvalido    NVARCHAR(200);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    DECLARE @EstudiantesATrabajar TABLE (secuencia INT IDENTITY(1,1), idEstudiante UNIQUEIDENTIFIER NULL, estado NVARCHAR(200) NULL);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Validacion completa del JSON antes de cualquier escritura (mismas reglas del lote congelado)
        IF @estadoResultado = 1
           AND (@asistenciaJSON IS NULL OR ISJSON(@asistenciaJSON, ARRAY) <> 1
                OR EXISTS (SELECT 1 FROM OPENJSON(@asistenciaJSON) item
                           WHERE item.[type] <> 5
                              OR (SELECT COUNT(1) FROM OPENJSON(item.value)) <> 2
                              OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) f WHERE f.[key] = 'idEstudiante')
                              OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) f WHERE f.[key] = 'estado')))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @EstudiantesATrabajar (idEstudiante, estado)
            SELECT TRY_CAST(idEstudiante AS UNIQUEIDENTIFIER), UPPER(TRIM(estado))
            FROM OPENJSON(@asistenciaJSON) WITH (idEstudiante NVARCHAR(100) '$.idEstudiante', estado NVARCHAR(200) '$.estado');
            SELECT @totalEstudiantes = COUNT(1) FROM @EstudiantesATrabajar;

            IF @totalEstudiantes = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @secuenciaInvalida = secuencia FROM @EstudiantesATrabajar WHERE idEstudiante IS NULL ORDER BY secuencia;
            IF @secuenciaInvalida IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idEstudiante',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @secuenciaInvalida = secuencia,
                   @estadoInvalido = CASE WHEN estado IS NULL OR estado = '' THEN N'(vacio)' ELSE estado END
            FROM @EstudiantesATrabajar
            WHERE estado IS NULL OR estado = '' OR estado NOT IN ('AN', 'SJC', 'EX')
            ORDER BY secuencia;
            IF @secuenciaInvalida IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RC_001', @p_param1 = @estadoInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteInvalido = idEstudiante FROM @EstudiantesATrabajar GROUP BY idEstudiante HAVING COUNT(1) > 1 ORDER BY idEstudiante;
            IF @idEstudianteInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_003', @p_param1 = @idEstudianteInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteInvalido = et.idEstudiante
            FROM @EstudiantesATrabajar et
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado
                WHERE eg.estudiante = et.idEstudiante AND eg.grupo = @idGrupo AND eeg.codigo = @codigoActiva)
            ORDER BY et.secuencia;
            IF @idEstudianteInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_004', @p_param1 = @idEstudianteInvalido, @p_param2 = @idSesion,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- Escritura atomica: ventana con tolerancia (bloquea Sesion) -> toma -> sincronizacion por estudiante
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_asistencias_toma;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
                SELECT @idSesion = t.sesion FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK) WHERE t.id = @idTomaDefecto;

            -- PC (puntos de control): una toma cerrada solo se corrige hasta que se abre la siguiente (TOM_012). Bajo el bloqueo
            -- de la Sesion (UPDLOCK, HOLDLOCK hasta el fin de la transaccion) ninguna apertura concurrente cambia esta respuesta.
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @p1 = CONVERT(NVARCHAR(20), t.numero), @p2 = CONVERT(NVARCHAR(20), t2.numero)
                FROM dbo.TomaAsistencia t
                INNER JOIN dbo.TomaAsistencia t2 ON t2.sesion = t.sesion AND t2.numero > t.numero
                WHERE t.id = @idTomaDefecto AND t.fechaCierreUtc IS NOT NULL
                ORDER BY t2.numero;
                IF @p2 IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_012', @p_param1 = @p1, @p_param2 = @p2,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            WHILE @iterador <= @totalEstudiantes AND @estadoResultado = 1
            BEGIN
                SELECT @idEstudianteActual = idEstudiante, @estadoActual = estado FROM @EstudiantesATrabajar WHERE secuencia = @iterador;
                SET @huboEscritura = 1;
                EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                    @idEstudiante = @idEstudianteActual, @idSesion = @idSesion, @codigoEstado = @estadoActual,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @idToma = @idTomaDefecto, @registradoPorEstudiante = 0, @soloSiNoExiste = 0, @idUsuarioEjecutor = @idUsuarioEjecutorDefecto;
                SET @iterador += 1;
            END

            -- La ventana debe seguir abierta en el punto de confirmacion
            IF @estadoResultado = 1
                EXEC dbo.usp_validar_sesion_ventana_registro_interno
                    @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                SET @p2 = CONVERT(NVARCHAR(20), @totalEstudiantes);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_010', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND (@estadoResultado = 1 OR @huboEscritura = 0)
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0 AND @huboEscritura = 1
                ROLLBACK TRANSACTION sp_asistencias_toma;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_asistencias_toma;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        totalRegistros          = IIF(@estadoResultado = 1, @totalEstudiantes, NULL);
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_tomas_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tomas_sesion (CULM-001 B.2, HU175; CONTRACT §2.8.4, §3.2.5 GET /sesiones/{id}/tomas)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion
-- falla). RBAC DOCENTE + titularidad sobre la sesion (SES_001 / SEC_001 / SEC_002 / GEN_002).
-- Filas: una por toma de la sesion (uv_toma_asistencia, orden numero) con los datos de la sesion y su ventana
-- (uv_sesion_estado: ventanaAperturaUtc, ventanaCierreUtc, ventanaAbierta, estaSesionCancelada, motivoCancelacion) y
-- maximoTomas (TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION). Una sesion SIN tomas devuelve una fila con los datos de la sesion
-- y las columnas de la toma en NULL (el docente ve la ventana antes de abrir la primera toma).
-- PC (puntos de control): columnas al final (NULL en la fila sin tomas):
--   fechaPuntoControlUtc, ordenPuntoControl, minutosTramoAnterior, minutosTramoSiguiente (uv_toma_asistencia);
--   esEditable       = ventana abierta y la toma es la abierta o no tiene toma posterior (regla TOM_012);
--   editableHastaUtc = apertura de la toma siguiente o, para la ultima, el cierre de la ventana (fin + margen).
-- horasToma (1/n) queda OBSOLETO: se conserva por compatibilidad; las horas salen de usp_consultar_resumen_tomas_sesion.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @maximoTomas          INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_sesion_exista_por_id_interno
            @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idSesion              = se.idSesion,
        idGrupo               = se.idGrupo,
        numeroSesion          = se.numero,
        horasSesion           = se.horasSesion,
        estaSesionCancelada   = se.estaCancelada,
        motivoCancelacion     = se.motivoCancelacion,
        ventanaAperturaUtc    = se.ventanaAperturaUtc,
        ventanaCierreUtc      = se.ventanaCierreUtc,
        ventanaAbierta        = se.ventanaAbierta,
        maximoTomas           = @maximoTomas,
        totalTomasSesion      = se.totalTomas,
        idToma                = t.idToma,
        numero                = t.numero,
        idModo                = t.idModo,
        codigoModo            = t.codigoModo,
        nombreModo            = t.nombreModo,
        usaCodigoQr           = t.usaCodigoQr,
        marcaAusentesAlCerrar = t.marcaAusentesAlCerrar,
        idEstado              = t.idEstado,
        codigoEstado          = t.codigoEstado,
        nombreEstado          = t.nombreEstado,
        estaAbierta           = t.estaAbierta,
        esImplicita           = t.esImplicita,
        idDocenteApertura     = t.idDocenteApertura,
        fechaAperturaUtc      = t.fechaAperturaUtc,
        fechaCierreUtc        = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        horasToma             = t.horasToma,
        totalRegistros        = t.totalRegistros,
        totalPresentes        = t.totalPresentes,
        totalAusentes         = t.totalAusentes,
        totalExcusas          = t.totalExcusas,
        tieneQrActivo         = t.tieneQrActivo,
        fechaPuntoControlUtc  = t.fechaPuntoControlUtc,
        ordenPuntoControl     = t.ordenPuntoControl,
        minutosTramoAnterior  = t.minutosTramoAnterior,
        minutosTramoSiguiente = t.minutosTramoSiguiente,
        esEditable            = CAST(IIF(t.idToma IS NULL, NULL,
                                         IIF(se.ventanaAbierta = 1 AND (t.estaAbierta = 1 OR t.fechaAperturaSiguienteUtc IS NULL), 1, 0)) AS BIT),
        editableHastaUtc      = CAST(IIF(t.idToma IS NULL, NULL, COALESCE(CAST(t.fechaAperturaSiguienteUtc AS DATETIME2(7)), se.ventanaCierreUtc)) AS DATETIME2(7))
    FROM dbo.uv_sesion_estado se
    LEFT JOIN dbo.uv_toma_asistencia t ON t.idSesion = se.idSesion
    WHERE se.idSesion = @idSesionDefecto
    ORDER BY t.numero ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_internal_radicar_solicitud_revision.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_radicar_solicitud_revision  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2, DEC-044 (3))
--
-- Nucleo interno COMUN de la radicacion de un reclamo: NO se concede a ningun rol. Lo invocan
-- usp_radicar_solicitud_revision_asistencia_v2 (un solo soporte) y _v3 (de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO) con
-- parametros OUTPUT, sin INSERT-EXEC (Msg 3915, DEC-036): no emite resultset; el llamador emite el suyo.
--
-- Orden (cada paso solo se evalua si los anteriores pasaron; un rechazo no escribe nada):
--   correlacion -> ejecutor -> RBAC ESTUDIANTE -> estudiante -> propiedad (H-01) -> sesion -> matricula
--   -> reejecucion idempotente por correlacion (algun soporte ya ATTACHED con la MISMA correlacion y del mismo dueno:
--      devuelve la solicitud y el total originales sin escribir)
--   -> PC (reclamo por toma, solo con @idToma; v2 y v3 no lo informan): toma de la sesion (TOM_001), SJC del estudiante en
--      esa toma con cabecera y detalle bloqueados (REV_026) y sin otra solicitud no retirada de la toma (REV_027)
--   -> plazo de excusas (usp_internal_validar_plazo_justificacion, D.1: REV_020 / REV_025; por sesion, igual para sus tomas)
--   -> categoria por codigo o por nombre (REV_021)
--   -> JSON valido (arreglo de GUID) y GUID distintos (GEN_002 / REV_024)
--   -> cantidad <= ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO (REV_023)
--   -> categoria con requiereSoporte y 0 soportes (REV_022)
--   -> cada soporte WITH (UPDLOCK, HOLDLOCK) en orden de id: dueno = ejecutor y estado ARCHIVO/ESTADO_BORRADOR
--      (inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin revelar el motivo)
--   -> INSERT de la solicitud (categoria y fecha LOCAL de radicacion) -> UPDATE de todos los soportes a ARCHIVO/ESTADO_ADJUNTO
--   -> verificacion por lectura de las N filas.
-- Los estados de soporte y de reclamo salen de parametros (TD-061), no de literales.
-- Ownership transaccional: transaccion propia si @@TRANCOUNT = 0, si no SAVE TRANSACTION (solo se revierte lo escrito).
-- En @estadoResultado = 1 con reejecucion idempotente no se escribe nada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_radicar_solicitud_revision]
(
    @idEstudiante             UNIQUEIDENTIFIER,
    @idSesion                 UNIQUEIDENTIFIER,
    @categoria                NVARCHAR(50),
    @justificacion            NVARCHAR(MAX),
    @idsArchivoSoporte        NVARCHAR(MAX),
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @idSolicitudRevision      UNIQUEIDENTIFIER OUTPUT,
    @totalSoportes            INT              OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idToma                   UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @estadoAdjunto            VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @estadoBorrador           VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @codigoPendiente          NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(5));
    DECLARE @codigoRetirado           NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5));
    DECLARE @codigoSinJustaCausa      NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(5));
    DECLARE @numeroToma               INT;
    DECLARE @codigoRazonToma          NVARCHAR(5);
    DECLARE @solicitudTomaExistente   UNIQUEIDENTIFIER;
    DECLARE @textoNumeroToma          NVARCHAR(20);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @idCategoria          UNIQUEIDENTIFIER;
    DECLARE @nombreCategoria      NVARCHAR(50);
    DECLARE @requiereSoporte      BIT = 0;

    -- Lista de soportes: @ids en el orden recibido; @ordenados sin repetidos y por id (orden fijo de bloqueo)
    DECLARE @ids TABLE (orden INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NULL);
    DECLARE @ordenados TABLE (pos INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NOT NULL);
    DECLARE @jsonValido           BIT = 1;
    DECLARE @cantidad             INT = 0;
    DECLARE @distintos            INT = 0;
    DECLARE @maximo               INT;
    DECLARE @pos                  INT = 1;
    DECLARE @idArchivo            UNIQUEIDENTIFIER;
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @solicitudSoporte     UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;
    DECLARE @textoCantidad        NVARCHAR(20);
    DECLARE @textoMaximo          NVARCHAR(20);
    DECLARE @descartado           NVARCHAR(4000);

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SET @idSolicitudRevision     = NULL;
    SET @totalSoportes           = 0;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Lista de soportes (arreglo JSON de GUID). Solo se lee aqui; los errores se informan en su turno.
        IF @idsArchivoSoporte IS NOT NULL AND LEN(TRIM(@idsArchivoSoporte)) > 0
        BEGIN
            IF ISJSON(@idsArchivoSoporte) = 1 AND LEFT(LTRIM(@idsArchivoSoporte), 1) = N'['
            BEGIN
                INSERT @ids (id)
                SELECT TRY_CAST(j.[value] AS UNIQUEIDENTIFIER)
                FROM OPENJSON(@idsArchivoSoporte) j
                ORDER BY CAST(j.[key] AS INT);
                IF EXISTS (SELECT 1 FROM OPENJSON(@idsArchivoSoporte) j WHERE j.[type] <> 1)
                   OR EXISTS (SELECT 1 FROM @ids WHERE id IS NULL)
                    SET @jsonValido = 0;
            END
            ELSE
                SET @jsonValido = 0;
        END
        SELECT @cantidad = COUNT(*), @distintos = COUNT(DISTINCT id) FROM @ids;

        -- PASO 9: Transaccion propia (o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_culm001_d2_radicar;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 10: Reejecucion idempotente por correlacion (antes del plazo: un reintento legitimo tras el vencimiento
        -- devuelve el exito original). Es un soporte ya vinculado con ESTA correlacion y del mismo dueno.
        IF @estadoResultado = 1 AND @jsonValido = 1 AND @cantidad > 0
        BEGIN
            SELECT TOP 1 @solicitudSoporte = a.solicitudRevisionAsistencia
            FROM dbo.ArchivoSoporte a
            INNER JOIN @ids i ON i.id = a.id
            WHERE a.estado = @estadoAdjunto
              AND a.idCorrelacionAdjuncion = @idCorrelacionDefecto
              AND a.usuarioPropietario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;
            IF @solicitudSoporte IS NOT NULL
            BEGIN
                SET @esReintento = 1;
                SET @idSolicitudRevision = @solicitudSoporte;
            END
        END

        -- PASO 10b (PC, reclamo por toma): con @idToma la toma debe ser de la sesion (TOM_001), el estudiante debe tener SJC en
        -- ella (REV_026; cabecera y detalle bloqueados) y no debe existir otra solicitud no retirada de la misma toma (REV_027).
        IF @estadoResultado = 1 AND @esReintento = 0 AND @idToma IS NOT NULL
        BEGIN
            SELECT @numeroToma = t.numero FROM dbo.TomaAsistencia t WHERE t.id = @idToma AND t.sesion = @idSesionDefecto;
            IF @numeroToma IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'TOM_001', @p_param1 = @idToma,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @textoNumeroToma = CONVERT(NVARCHAR(20), @numeroToma);
                SELECT TOP 1 @idEstudianteGrupo = eg.id
                FROM dbo.Sesion s
                INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
                WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

                SELECT TOP 1 @idAsistencia = a.id, @codigoRazonToma = rc.codigo
                FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK)
                LEFT JOIN dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK) ON d.asistencia = a.id AND d.toma = @idToma
                LEFT JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                WHERE a.estudianteGrupo = @idEstudianteGrupo AND a.sesion = @idSesionDefecto;

                IF @codigoRazonToma IS NULL OR @codigoRazonToma <> @codigoSinJustaCausa
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'REV_026', @p_param1 = @textoNumeroToma, @p_param2 = @idSesionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    SELECT TOP 1 @solicitudTomaExistente = sra.id
                    FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Estado e ON e.id = sra.estado
                    WHERE sra.asistencia = @idAsistencia AND sra.toma = @idToma AND e.codigo <> @codigoRetirado
                    ORDER BY sra.id;
                    IF @solicitudTomaExistente IS NOT NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_027', @p_param1 = @textoNumeroToma, @p_param2 = @solicitudTomaExistente,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                        SET @estadoResultado = 0;
                    END
                END
            END
            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 11: Plazo de excusas (D.1). Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 12: Categoria por codigo o por nombre (el codigo gana si ambos coinciden con filas distintas)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SELECT TOP 1 @idCategoria = c.id, @nombreCategoria = c.nombre, @requiereSoporte = c.requiereSoporte
            FROM dbo.CategoriaJustificacion c
            WHERE c.codigo = @categoriaDefecto OR c.nombre = @categoriaDefecto
            ORDER BY IIF(c.codigo = @categoriaDefecto, 0, 1), c.id;
            IF @idCategoria IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_021', @p_param1 = @categoriaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 13: JSON valido y soportes distintos
        IF @estadoResultado = 1 AND @esReintento = 0 AND @jsonValido = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idsArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad <> @distintos
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_024',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 14: Cantidad maxima de soportes (ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @maximo = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO');
            IF @maximo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002', @p_param1 = 'ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @cantidad > @maximo
            BEGIN
                SET @textoCantidad = CONVERT(NVARCHAR(20), @cantidad);
                SET @textoMaximo = CONVERT(NVARCHAR(20), @maximo);
                -- El mensaje de usuario usa solo {1} (maximo); el tecnico usa {1}=cantidad, {2}=maximo.
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoMaximo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @descartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoCantidad, @p_param2 = @textoMaximo,
                    @mensajeUsuarioResultado = @descartado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 15: Soporte obligatorio segun la categoria (HU014)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @requiereSoporte = 1 AND @cantidad = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_022', @p_param1 = @nombreCategoria,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 16: Bloqueo de cada soporte en orden de id (UPDLOCK, HOLDLOCK serializa radicaciones concurrentes con el mismo fileId)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad > 0
        BEGIN
            INSERT @ordenados (id) SELECT DISTINCT id FROM @ids ORDER BY id;
            WHILE @pos <= (SELECT COUNT(*) FROM @ordenados) AND @estadoResultado = 1 AND @esReintento = 0
            BEGIN
                SELECT @idArchivo = o.id FROM @ordenados o WHERE o.pos = @pos;
                SET @propietarioSoporte = NULL; SET @estadoSoporte = NULL; SET @correlacionAdjuncion = NULL; SET @solicitudSoporte = NULL;
                SELECT @propietarioSoporte   = a.usuarioPropietario,
                       @estadoSoporte        = a.estado,
                       @correlacionAdjuncion = a.idCorrelacionAdjuncion,
                       @solicitudSoporte     = a.solicitudRevisionAsistencia
                FROM dbo.ArchivoSoporte a WITH (UPDLOCK, HOLDLOCK)
                WHERE a.id = @idArchivo;

                IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
                BEGIN
                    SET @estadoResultado = 0;
                END
                ELSE IF @estadoSoporte = @estadoAdjunto AND @correlacionAdjuncion = @idCorrelacionDefecto
                BEGIN
                    -- Carrera con la misma solicitud (doble envio): la otra sesion ya confirmo; es una reejecucion
                    SET @esReintento = 1;
                    SET @idSolicitudRevision = @solicitudSoporte;
                END
                ELSE IF @estadoSoporte <> @estadoBorrador
                BEGIN
                    SET @estadoResultado = 0;
                END

                IF @estadoResultado = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
                SET @pos += 1;
            END
        END

        -- PASO 17: Creacion de la solicitud y vinculo atomico de los N soportes
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SET @fechaLocalRadicacion = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE);

            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo = @codigoPendiente ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta, categoriaJustificacion, toma
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                '',
                @idCategoria,
                @idToma
            );

            IF @cantidad > 0
            BEGIN
                UPDATE a
                SET estado = @estadoAdjunto,
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                FROM dbo.ArchivoSoporte a
                INNER JOIN @ordenados o ON o.id = a.id
                WHERE a.estado = @estadoBorrador
                  AND a.usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): los N soportes quedaron vinculados a ESTA solicitud.
                IF @filasActualizadas <> @cantidad
                   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN @ordenados o ON o.id = a.id
                       WHERE a.estado = @estadoAdjunto AND a.solicitudRevisionAsistencia = @nuevaSolicitudId) <> @cantidad
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            IF @estadoResultado = 1
                SET @idSolicitudRevision = @nuevaSolicitudId;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @totalSoportes = COUNT(*) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @idSolicitudRevision;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
        ELSE
        BEGIN
            SET @idSolicitudRevision = NULL;
            SET @totalSoportes = 0;
        END

        -- PASO 18: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_resolver_solicitud_revision_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-04: resolucion del reclamo de inasistencia por el docente titular (flujo formal posterior al cierre).
--   * @accion: exactamente APROBADA o RECHAZADA (TRIM + UPPER). Cualquier otro valor => REV_001, sin escrituras.
--   * APROBADA: la asistencia queda JUSTIFICADA = RazonCausa EX con asistio = 0 (no es presencia AN). La solicitud pasa
--     a A. Si la asistencia ya era EX solo se resuelve la solicitud. Una asistencia AN no es justificable => REV_003.
--   * RECHAZADA: la solicitud pasa a R y DetalleAsistencia NO se modifica.
--   * Concurrencia: la solicitud se lee con UPDLOCK/HOLDLOCK dentro de la transaccion; dos resoluciones simultaneas se
--     serializan. Reintento con la misma decision ya aplicada => exito idempotente sin nuevas escrituras ni auditoria;
--     decision contradictoria sobre una solicitud ya resuelta => REV_002.
--   * Solicitud inexistente => REV_005; docente no titular => VAL_007 (contrato previo); sin detalle de asistencia
--     => REV_004 (no se simula una justificacion ni se crean filas).
--   * Auditoria oficial (dbo.AuditoriaEvento) en la MISMA transaccion: actor, accion, estado previo y nuevo de la
--     solicitud y del detalle, respuesta y correlacion.
--   * No usa la ventana de registro ordinario (SES-01): la rectificacion por reclamo es valida despues del cierre.
--   * Resultset canonico de 4 columnas sin cambio.
-- PC (puntos de control, reclamo por toma): parametro opcional al final @codigoResultadoAprobacion (NULL = EX):
--   * valores validos ASISTENCIA/CODIGO_RAZON_PRESENTE (AN, "si estuvo presente") y ASISTENCIA/CODIGO_RAZON_EXCUSA (EX,
--     "ausencia justificada"); cualquier otro => REV_028, sin escrituras.
--   * Solicitud CON toma: se bloquea y modifica solo el detalle (asistencia, toma). APROBADA + AN => AN con asistio = 1;
--     APROBADA + EX => EX con asistio = 0, solo en esa toma; RECHAZADA no toca el detalle. Sin detalle REV_004; detalle AN REV_003.
--   * Solicitud SIN toma (reclamo de la sesion, legado): APROBADA + AN => REV_029; EX conserva SES-04 (todos los SJC pasan a EX).
--   * La aprobacion guarda razonCausaResolucion. Reintento con la misma accion y el mismo resultado => exito sin escrituras;
--     resultado distinto sobre una solicitud ya aprobada (sin resultado guardado cuenta como EX) => REV_002.
--   * La auditoria agrega idToma y resultadoAprobacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_revision_asistencia]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @accion             NVARCHAR(20),
    @respuestaDocente   NVARCHAR(MAX),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoResultadoAprobacion NVARCHAR(5) = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionDefecto            NVARCHAR(20)     = UPPER(TRIM(@accion));
    DECLARE @respuestaDefecto         NVARCHAR(MAX)    = TRIM(@respuestaDocente);

    DECLARE @docenteTitularGrupo   UNIQUEIDENTIFIER;
    DECLARE @idAsistencia          UNIQUEIDENTIFIER;
    DECLARE @idDetalle             UNIQUEIDENTIFIER;
    DECLARE @asistioAnterior       BIT;
    DECLARE @codigoCausaAnterior   NVARCHAR(5);
    DECLARE @codigoEstadoActual    CHAR(1);
    DECLARE @codigoEstadoNuevo     CHAR(1);
    DECLARE @idEstadoNuevo         UNIQUEIDENTIFIER;
    DECLARE @idRazonJustificada    UNIQUEIDENTIFIER;
    DECLARE @modificaDetalle       BIT = 0;
    DECLARE @codigoPresente        NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_PRESENTE') AS NVARCHAR(5));
    DECLARE @codigoExcusa          NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_EXCUSA') AS NVARCHAR(5));
    DECLARE @codigoResultado       NVARCHAR(5);
    DECLARE @codigoResultadoPrevio NVARCHAR(5);
    DECLARE @idTomaSolicitud       UNIQUEIDENTIFIER;
    DECLARE @idRazonResultado      UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: El ejecutor es obligatorio y debe tener perfil DOCENTE
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (SES-04): solo las acciones contractuales; ningun otro valor se interpreta como rechazo
        IF @estadoResultado = 1 AND (@accionDefecto IS NULL OR @accionDefecto NOT IN (N'APROBADA', N'RECHAZADA'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_001',
                @p_param1 = @accion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 1.7 (PC): resultado de la aprobacion (NULL = EX); solo AN o EX
        SET @codigoResultado = UPPER(TRIM(ISNULL(@codigoResultadoAprobacion, @codigoExcusa)));
        IF @estadoResultado = 1 AND (@codigoResultado IS NULL OR @codigoResultado NOT IN (@codigoPresente, @codigoExcusa))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_028',
                @p_param1 = @codigoResultadoAprobacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Resolución atómica. La solicitud, su estado y su detalle se leen bajo bloqueo dentro de la
        --         transacción; los rechazos de negocio confirman una transacción sin escrituras (así no hay ROLLBACK
        --         dentro de un INSERT ... EXEC del llamador).
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            SELECT TOP 1
                @docenteTitularGrupo = g.docente,
                @idAsistencia = sra.asistencia,
                @codigoEstadoActual = e.codigo,
                @idTomaSolicitud = sra.toma,
                @codigoResultadoPrevio = rcr.codigo
            FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado e ON e.id = sra.estado
            LEFT JOIN dbo.RazonCausa rcr ON rcr.id = sra.razonCausaResolucion
            INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
            INNER JOIN dbo.Sesion s ON ast.sesion = s.id
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE sra.id = @idSolicitudDefecto;

            -- 2.1: solicitud existente con relacion solicitud -> asistencia -> sesion -> grupo
            IF @docenteTitularGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_005',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2: titularidad del docente sobre el grupo de la sesion
            ELSE IF @docenteTitularGrupo <> @idDocenteDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'DocenteAmbitoRevision',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2b (PC): "si estuvo presente" solo aplica a un reclamo de una toma
            ELSE IF @accionDefecto = N'APROBADA' AND @idTomaSolicitud IS NULL AND @codigoResultado = @codigoPresente
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_029',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @codigoEstadoNuevo = CASE WHEN @accionDefecto = N'APROBADA' THEN 'A' ELSE 'R' END;

                -- 2.3: solo una solicitud pendiente se resuelve. La misma decision ya aplicada es un reintento
                --      idempotente (sin escrituras); una decision distinta es un conflicto. PC: una aprobacion con otro
                --      resultado tambien es un conflicto (sin resultado guardado, la aprobacion anterior fue EX).
                IF @codigoEstadoActual <> 'P'
                BEGIN
                    IF @codigoEstadoActual <> @codigoEstadoNuevo
                       OR (@codigoEstadoNuevo = 'A' AND ISNULL(@codigoResultadoPrevio, @codigoExcusa) <> @codigoResultado)
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_002',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                END
                ELSE
                BEGIN
                    -- 2.4: detalle de la asistencia (bloqueado). Sin detalle no se simula una justificacion.
                    -- CULM-001 B.2 (CONTRACT §2.9): con varias tomas se bloquean todos los detalles de la asistencia y el
                    -- representativo es el de estado consolidado (SJC antes que EX antes que AN): con una toma, el mismo de antes.
                    SELECT TOP 1
                        @idDetalle = d.id,
                        @asistioAnterior = d.asistio,
                        @codigoCausaAnterior = rc.codigo
                    -- PC: con toma, solo el detalle de esa toma.
                    FROM dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                    WHERE d.asistencia = @idAsistencia
                      AND (@idTomaSolicitud IS NULL OR d.toma = @idTomaSolicitud)
                    ORDER BY CASE rc.codigo WHEN N'SJC' THEN 0 WHEN N'EX' THEN 1 ELSE 2 END, d.id;

                    IF @idDetalle IS NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_004',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                    -- 2.5: solo una ausencia es justificable; una presencia (AN / asistio = 1) no se aprueba
                    ELSE IF @codigoEstadoNuevo = 'A' AND (@asistioAnterior = 1 OR @codigoCausaAnterior = N'AN')
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_003',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END

                    -- 2.6: catalogos cerrados (Estado A/R, RazonCausa EX); nunca se elige otra fila
                    IF @estadoResultado = 1
                    BEGIN
                        SELECT @idEstadoNuevo = id FROM dbo.Estado WHERE codigo = @codigoEstadoNuevo;
                        SELECT @idRazonJustificada = id FROM dbo.RazonCausa WHERE codigo = @codigoResultado;
                        IF @idEstadoNuevo IS NULL OR (@codigoEstadoNuevo = 'A' AND @idRazonJustificada IS NULL)
                            THROW 52401, 'SES04_CATALOGO_INCONSISTENTE: falta Estado A/R o RazonCausa EX.', 1;

                        SET @modificaDetalle = CASE WHEN @codigoEstadoNuevo = 'A' AND @codigoCausaAnterior <> @codigoResultado THEN 1 ELSE 0 END;

                        -- 2.7: la solicitud queda resuelta con la respuesta del docente (PC: y el resultado si se aprueba)
                        UPDATE dbo.SolicitudRevisionAsistencia
                        SET estado = @idEstadoNuevo,
                            justificacionRespuesta = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END,
                            razonCausaResolucion = CASE WHEN @codigoEstadoNuevo = 'A' THEN @idRazonJustificada ELSE razonCausaResolucion END
                        WHERE id = @idSolicitudDefecto;

                        -- 2.8: aprobacion => resultado (EX con asistio = 0, o AN con asistio = 1 si el reclamo es de una toma).
                        --      Sin toma (legado) todos los SJC pasan a EX; con toma solo su detalle. El rechazo no toca DetalleAsistencia.
                        IF @modificaDetalle = 1
                        BEGIN
                            UPDATE d
                            SET razonCausa = @idRazonJustificada,
                                asistio = IIF(@codigoResultado = @codigoPresente, 1, 0)
                            FROM dbo.DetalleAsistencia d
                            INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                            WHERE d.asistencia = @idAsistencia
                              AND (d.id = @idDetalle OR (@idTomaSolicitud IS NULL AND rc.codigo = N'SJC'));
                        END

                        -- 2.9: auditoria oficial con estado previo y nuevo, en la misma transaccion
                        INSERT INTO dbo.AuditoriaEvento (
                            id, occurredAt, actorId, actorType, action,
                            resourceType, resourceId, result, correlationId,
                            httpMethod, path, httpStatus, metadata
                        ) VALUES (
                            NEWID(),
                            SYSDATETIMEOFFSET(),
                            CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)),
                            'USER',
                            'RESOLVER_SOLICITUD_REVISION_ASISTENCIA',
                            'SolicitudRevisionAsistencia',
                            CAST(@idSolicitudDefecto AS NVARCHAR(120)),
                            'SUCCESS',
                            @idCorrelacionDefecto,
                            'PATCH',
                            N'/api/v1/docente/reclamos/{id}',
                            200,
                            (SELECT accion = @accionDefecto,
                                    estadoSolicitudAnterior = @codigoEstadoActual,
                                    estadoSolicitudNuevo = @codigoEstadoNuevo,
                                    idAsistencia = CAST(@idAsistencia AS NVARCHAR(36)),
                                    idDetalleAsistencia = CAST(@idDetalle AS NVARCHAR(36)),
                                    razonCausaAnterior = @codigoCausaAnterior,
                                    asistioAnterior = @asistioAnterior,
                                    razonCausaNueva = CASE WHEN @modificaDetalle = 1 THEN @codigoResultado ELSE @codigoCausaAnterior END,
                                    asistioNuevo = CASE WHEN @modificaDetalle = 1 THEN CAST(IIF(@codigoResultado = @codigoPresente, 1, 0) AS BIT) ELSE @asistioAnterior END,
                                    respuestaDocente = @respuestaDefecto,
                                    idToma = CAST(@idTomaSolicitud AS NVARCHAR(36)),
                                    resultadoAprobacion = CASE WHEN @codigoEstadoNuevo = 'A' THEN @codigoResultado END
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                        );
                    END
                END
            END

            COMMIT TRANSACTION;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'SolicitudRevisionAsistencia',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_revision_estudiante.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_estudiante  (HU010/HU011, consulta)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance (ownership en persistencia): SOLO solicitudes cuya cadena
-- SolicitudRevisionAsistencia -> Asistencia -> EstudianteGrupo -> Estudiante tiene Estudiante.usuario = ejecutor.
-- Otro estudiante, un docente o un coordinador => 0 filas. Une tablas base; no usa SESSION_CONTEXT ni uv_auth_*.
-- Resultset con las MISMAS columnas y tipos que usp_consultar_solicitudes_revision_docente (R2, LB-004D):
-- idEstudiante/nombreEstudiante son los del propio ejecutor. El soporte vinculado se resuelve con el
-- parametro ARCHIVO.ESTADO_ADJUNTO (sin literales quemados), igual que el detalle HU035/HU036.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: solo el nombre del propio estudiante, sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
-- PC (puntos de control, reclamo por toma): AL FINAL idToma, numeroToma y fechaPuntoControlUtc de la toma reclamada (NULL en un
-- reclamo de la sesion completa) y codigoResultadoAprobacion (AN = estuvo presente, EX = ausencia justificada; NULL si no aprobado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_estudiante]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @estadoAdjunto VARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        totalRegistros                = COUNT(*) OVER(),
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]'),
        idToma                        = sra.toma,
        numeroToma                    = pct.numero,
        fechaPuntoControlUtc          = pct.fechaPuntoControlUtc,
        codigoResultadoAprobacion     = rcr.codigo
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    LEFT  JOIN dbo.uv_toma_punto_control pct  ON pct.idToma = sra.toma AND pct.idSesion = asi.sesion
    LEFT  JOIN dbo.RazonCausa rcr             ON rcr.id = sra.razonCausaResolucion
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_detalle_solicitud_revision_docente.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solicitud de revision).
-- Los parametros invalidos se propagan con THROW (como usp_consultar_solicitudes_revision_docente, R2).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Solicitud inexistente o ajena => 0 filas (no distingue
-- ambos casos para no revelar existencia). Solo lectura: sin transaccion explicita.
--
-- Causal: DetalleAsistencia y RazonCausa se unen con LEFT JOIN (la solicitud existe aunque falte el detalle).
-- Soporte: ArchivoSoporte se une con LEFT JOIN y solo en el estado definido por el parametro
-- ARCHIVO.ESTADO_ADJUNTO (sin literales quemados).
--
-- Semantica temporal: igual que R2. fechaSolicitud es DATE de calendario; fechaHoraInicioSesion es el
-- DATETIME2(7) de dbo.Sesion TAL CUAL con procedenciaTemporalSesion (NULL = INDETERMINADA, historica);
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7). Datos personales minimos: sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
-- PC (puntos de control, reclamo por toma): AL FINAL idToma, numeroToma, fechaPuntoControlUtc (NULL en un reclamo de la sesion),
-- codigoResultadoAprobacion (AN/EX), codigoRazonCausaToma (marca actual del estudiante en la toma reclamada; NULL sin detalle) y
-- minutosSesion / minutosAsistidos de la sesion por tramos (uv_asistencia_sesion_horas; NULL sin cabecera).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_detalle_solicitud_revision_docente]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idSolicitud IS NULL OR @idSolicitudDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'Solicitud',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        asistio                       = CAST(CASE WHEN det.codigoRazonCausaConsolidado IS NULL THEN NULL WHEN det.codigoRazonCausaConsolidado = N'AN' THEN 1 ELSE 0 END AS BIT),
        codigoRazonCausa              = rzc.codigo,
        nombreRazonCausa              = rzc.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]'),
        idToma                        = sra.toma,
        numeroToma                    = pct.numero,
        fechaPuntoControlUtc          = pct.fechaPuntoControlUtc,
        codigoResultadoAprobacion     = rcr.codigo,
        codigoRazonCausaToma          = rct.codigo,
        minutosSesion                 = det.minutosSesion,
        minutosAsistidos              = det.minutosAsistidos
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    -- CULM-001 B.2 (CONTRACT §2.9): estado consolidado de la sesion (una fila aunque haya varias tomas)
    OUTER APPLY (SELECT h.codigoRazonCausaConsolidado, h.minutosSesion, h.minutosAsistidos
                 FROM dbo.uv_asistencia_sesion_horas h WHERE h.idAsistencia = asi.id) det
    LEFT  JOIN dbo.RazonCausa rzc         ON rzc.codigo = det.codigoRazonCausaConsolidado
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    -- PC (puntos de control): toma reclamada, su marca actual y el resultado de la aprobacion
    LEFT  JOIN dbo.uv_toma_punto_control pct  ON pct.idToma = sra.toma AND pct.idSesion = asi.sesion
    LEFT  JOIN dbo.RazonCausa rcr             ON rcr.id = sra.razonCausaResolucion
    LEFT  JOIN dbo.DetalleAsistencia dtt      ON dtt.asistencia = asi.id AND dtt.toma = sra.toma
    LEFT  JOIN dbo.RazonCausa rct             ON rct.id = dtt.razonCausa
    WHERE sra.id = @idSolicitudDefecto
      AND doc.usuario = @idUsuarioDefecto;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_resumen_tomas_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_tomas_sesion (PC puntos de control; docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B;
-- GET /api/v1/sesiones/{sesionId}/tomas/resumen)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion falla).
-- Validacion compartida usp_validar_docente_titular_sesion_interno: correlacion, ejecutor y sesion obligatorios (GEN_002),
-- RBAC DOCENTE (SEC_001) y titularidad sobre la sesion (SEC_002).
-- Filas: una por matricula activa (MATRICULA/ESTADO_INSCRITA) del grupo de la sesion, ordenadas por nombre, con los minutos de
-- la sesion por tramos entre puntos de control (uv_asistencia_sesion_horas). Sin cabecera Asistencia: minutosSinRegistro =
-- minutosSesion, los demas en 0 y estado NO_DISPONIBLE.
-- Columnas: idEstudiante, nombreCompletoEstudiante, minutosSesion, minutosAsistidos, minutosFalta, minutosExcusa,
-- minutosSinRegistro, codigoEstadoSesionEstudiante, tomasAusentes.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idSesionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoActiva     NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;

    EXEC dbo.usp_validar_docente_titular_sesion_interno
        @idSesion = @idSesion, @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idEstudiante                 = eg.idEstudiante,
        nombreCompletoEstudiante     = eg.nombreCompletoEstudiante,
        minutosSesion                = ms.minutosSesion,
        minutosAsistidos             = ISNULL(h.minutosAsistidos, 0),
        minutosFalta                 = ISNULL(h.minutosFalta, 0),
        minutosExcusa                = ISNULL(h.minutosExcusa, 0),
        minutosSinRegistro           = ISNULL(h.minutosSinRegistro, ms.minutosSesion),
        codigoEstadoSesionEstudiante = ISNULL(h.codigoEstadoSesionEstudiante, CAST(N'NO_DISPONIBLE' AS NVARCHAR(20))),
        tomasAusentes                = ISNULL(h.tomasAusentes, 0)
    FROM dbo.Sesion s
    CROSS APPLY (SELECT minutosSesion = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin), 0)) ms
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = @codigoActiva
    LEFT JOIN dbo.uv_asistencia_sesion_horas h ON h.idSesion = s.id AND h.idEstudianteGrupo = eg.id
    WHERE s.id = @idSesionDefecto
    ORDER BY eg.nombreCompletoEstudiante ASC, eg.idEstudiante ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v4.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v4  (PC puntos de control: reclamo POR TOMA; docs/work-items/PC-puntos-control-tomas)
--
-- Igual que _v3 (categoria persistida y de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO soportes) pero el reclamo es de UNA toma:
--   @idToma obligatorio (GEN_002 si es NULL). Solo se reclama una toma de la sesion (TOM_001) en la que el estudiante quedo
--   ausente (SJC, REV_026) y sin otra solicitud no retirada de esa toma (REV_027): un reclamo retirado permite radicar otro; uno
--   rechazado o aprobado no. El plazo HU026B es el de la sesion (REV_020 / REV_025).
-- Toda la logica y la transaccion viven en usp_internal_radicar_solicitud_revision (transaccion propia si @@TRANCOUNT = 0, si no
-- SAVE TRANSACTION; un rechazo no escribe). _v3 se conserva para el reclamo de la sesion completa (compatibilidad).
--
-- Resultset: MUTATION_COMMAND_RESULTSET extendido: las 4 columnas canonicas + idSolicitudRevision, totalSoportes e idToma
-- (NULL / 0 / NULL si fallo).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v4]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @idToma             UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idsArchivoSoporte  NVARCHAR(MAX) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudRevision     UNIQUEIDENTIFIER = NULL;
    DECLARE @totalSoportes           INT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    IF @idToma IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idToma',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    ELSE
        EXEC dbo.usp_internal_radicar_solicitud_revision
            @idEstudiante = @idEstudiante,
            @idSesion = @idSesion,
            @categoria = @categoria,
            @justificacion = @justificacion,
            @idsArchivoSoporte = @idsArchivoSoporte,
            @idCorrelacion = @idCorrelacionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idSolicitudRevision = @idSolicitudRevision OUTPUT,
            @totalSoportes = @totalSoportes OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idToma = @idToma;

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSolicitudRevision     = @idSolicitudRevision,
        totalSoportes           = @totalSoportes,
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL);
END;
GO
GO
-- ---- schema/security/rol_asistencias_runtime_puntos_control.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas): permisos del rol runtime para lo nuevo. Aditivo e idempotente.
--   EXECUTE: usp_radicar_solicitud_revision_asistencia_v4 (reclamo por toma) y usp_consultar_resumen_tomas_sesion (docente).
--   SELECT:  uv_asistencia_toma_estudiante (la lee el backend por JPA). uv_asistencia_sesion_horas y uv_toma_asistencia ya
--            tienen SELECT (rol_asistencias_runtime_culm001_b2.sql). Las vistas uv_* reciben ademas el SELECT generico de
--            rol_asistencias_runtime.sql; este archivo lo deja explicito para la vista que consume el backend.
-- usp_internal_radicar_solicitud_revision sigue sin concederse (encadenamiento de propiedad).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v4', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_radicar_solicitud_revision_asistencia_v4] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_resumen_tomas_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_resumen_tomas_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_asistencia_toma_estudiante', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_asistencia_toma_estudiante] TO [rol_asistencias_runtime];
GO
GO
-- ---- SELECT de las vistas internas nuevas: deploy_schema.ps1 se lo da con el bucle uv_* de rol_asistencias_runtime.sql (seguridad despues de
-- las vistas); la migracion lo replica para que una BD migrada y una desplegada queden iguales.
IF OBJECT_ID(N'dbo.uv_toma_punto_control', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_toma_punto_control] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_asistencia_tramo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_asistencia_tramo] TO [rol_asistencias_runtime];
GO
-- ---- schema/seed/61_puntos_control_mensajes.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B): mensajes del ciclo de vida de la toma y del
-- reclamo por toma. Idempotente (MERGE por codigo).
--   TOM_012 la toma cerrada ya no se puede corregir porque se abrio la siguiente (409).
--   REV_026 la toma reclamada no tiene ausencia (SJC) del estudiante (409).
--   REV_027 ya existe un reclamo no retirado para esa toma (409).
--   REV_028 resultado de aprobacion distinto de PRESENTE (AN) o JUSTIFICADA (EX) (400).
--   REV_029 la aprobacion como presente solo aplica a reclamos de una toma (409).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('TOM_012', 'BUSINESS_ERROR',   'MEDIO', N'La toma {} ya no se puede corregir porque se abrió la toma {}. Las correcciones se hacen por reclamo del estudiante.'),
    ('REV_026', 'BUSINESS_ERROR',   'MEDIO', N'Solo puedes reclamar una toma en la que quedaste ausente.'),
    ('REV_027', 'BUSINESS_ERROR',   'MEDIO', N'Ya existe un reclamo para esta toma.'),
    ('REV_028', 'VALIDATION_ERROR', 'BAJO',  N'El resultado de la aprobación debe ser PRESENTE o JUSTIFICADA.'),
    ('REV_029', 'BUSINESS_ERROR',   'MEDIO', N'La aprobación como presente solo aplica a reclamos de una toma.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('TOM_012', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la toma numero [{}] esta cerrada y ya se abrio la toma numero [{}]; solo se corrige por reclamo; sin escrituras.'),
    ('REV_026', 'BUSINESS_ERROR',   'MEDIO', N'Regla: el estudiante no tiene SJC en la toma [{}] de la sesion [{}]; sin escrituras.'),
    ('REV_027', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la toma [{}] ya tiene la solicitud de revision no retirada [{}]; sin escrituras.'),
    ('REV_028', 'VALIDATION_ERROR', 'BAJO',  N'Validacion: codigoResultadoAprobacion [{}] fuera de ASISTENCIA/CODIGO_RAZON_PRESENTE y ASISTENCIA/CODIGO_RAZON_EXCUSA; sin escrituras.'),
    ('REV_029', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la solicitud de revision [{}] es de la sesion completa (sin toma) y solo admite el resultado EX; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
GO
-- ---- datos (schema/seed/35_parametros_toma_asistencia_qr.sql y 35_catalogos_toma_asistencia.sql): el MERGE de la semilla no pisa el valor
-- administrado, asi que el tope sube a 20 solo si sigue en 4; el modo MANUAL pasa a marcar ausentes al cerrar.
UPDATE dbo.CatalogoParametro
SET    valor = N'20', fechaModificacion = SYSUTCDATETIME()
WHERE  grupo = 'TOMA_ASISTENCIA' AND clave = 'MAXIMO_TOMAS_POR_SESION' AND valor = N'4';
UPDATE dbo.CatalogoParametro
SET    valorDefecto = N'20', fechaModificacion = SYSUTCDATETIME()
WHERE  grupo = 'TOMA_ASISTENCIA' AND clave = 'MAXIMO_TOMAS_POR_SESION' AND valorDefecto = N'4';
UPDATE dbo.ModoTomaAsistencia SET marcaAusentesAlCerrar = 1 WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000001' AND marcaAusentesAlCerrar = 0;
GO
PRINT 'MIGRACION 37 UP OK';
GO
