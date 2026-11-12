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
