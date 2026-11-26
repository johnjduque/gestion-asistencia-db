USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_docente  (LB-004D, R2)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Otro docente => 0 filas. Une tablas base; no usa
-- SESSION_CONTEXT ni uv_auth_*.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: nombre del estudiante, sin correo.
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060/TD-061): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las
-- del PRIMER soporte adjuntado (contrato posicional) y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a
-- la categoria persistida) y totalSoportes. El estado adjunto sale de ARCHIVO/ESTADO_ADJUNTO (sin literal 'quemado').
-- PC (puntos de control, mejora bandeja 2026-11-12, migracion 38): AL FINAL idToma, numeroToma y fechaPuntoControlUtc de la toma reclamada
-- (NULL en un reclamo de la sesion completa), con la misma resolucion que usp_consultar_detalle_solicitud_revision_docente.
-- CIERRE-W1A (docs/work-items/CIERRE-W1A-docente-reclamos-padron/CONTRACT.md): dos filtros opcionales AL FINAL de los parametros (el resultset NO cambia):
--   @busqueda  subcadena (CHARINDEX, collation de la BD) en el nombre del estudiante, nombre y codigo de la asignatura y la justificacion de la solicitud;
--   @idGrupo   solo las solicitudes de ese grupo. La titularidad (doc.usuario = ejecutor) se mantiene, asi que un grupo ajeno da 0 filas.
-- Con ambos NULL el comportamiento es el anterior. totalRegistros (COUNT OVER) ya cuenta con los filtros.
-- ============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE en la cabecera, PASO n, lecturas por vistas uv_* (reclamo, estado, asistencia, matricula,
-- estudiante, usuario, sesion, grupo, docente, asignatura, soporte y categoria; antes, las tablas) y TRY/CATCH de lectura que relanza
-- (antes, sin TRY). El manifiesto LB-004D se regenera en el mismo commit.
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10,
    @busqueda           NVARCHAR(100)    = NULL,
    @idGrupo            UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @busquedaFiltro NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @estadoAdjunto VARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paginacion protegida (minimo 1, maximo 100)

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (VAL_001)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 3: rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: reclamos de las sesiones del docente, filtrados y paginados
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
            totalSoportes                 = (SELECT COUNT(*) FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id),
            idToma                        = sra.idToma,
            numeroToma                    = pct.numero,
            fechaPuntoControlUtc          = pct.fechaPuntoControlUtc
        FROM dbo.uv_solicitud_revision_asistencia_registro sra
        INNER JOIN dbo.uv_estado est                   ON est.id = sra.idEstado
        INNER JOIN dbo.uv_asistencia_registro asi      ON asi.id = sra.idAsistencia
        INNER JOIN dbo.uv_estudiante_grupo_registro eg ON eg.id = asi.idEstudianteGrupo
        INNER JOIN dbo.uv_estudiante_identidad estu    ON estu.id = eg.idEstudiante
        INNER JOIN dbo.uv_usuario usu                  ON usu.id = estu.idUsuario
        INNER JOIN dbo.uv_sesion_registro ses          ON ses.id = asi.idSesion
        INNER JOIN dbo.uv_grupo_registro gru           ON gru.id = ses.idGrupo
        INNER JOIN dbo.uv_docente_identidad doc        ON doc.id = gru.idDocente
        INNER JOIN dbo.uv_asignatura_registro asg      ON asg.id = gru.idAsignatura
        OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                     FROM dbo.uv_archivo_soporte_registro a
                     WHERE a.idSolicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                     ORDER BY a.fechaAdjuncionUtc, a.id) arc
        LEFT  JOIN dbo.uv_categoria_justificacion cat ON cat.id = sra.idCategoriaJustificacion
        -- PC (puntos de control): toma reclamada (LEFT JOIN: NULL en un reclamo de la sesion completa)
        LEFT  JOIN dbo.uv_toma_punto_control pct  ON pct.idToma = sra.idToma AND pct.idSesion = asi.idSesion
        WHERE doc.idUsuario = @idUsuarioDefecto
          AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
          AND (@idGrupo IS NULL OR gru.id = @idGrupo)
          AND (@busquedaFiltro IS NULL
               OR CHARINDEX(@busquedaFiltro, CONCAT_WS(N' ',
                      NULLIF(TRIM(usu.primerNombre), N''), NULLIF(TRIM(usu.segundoNombre), N''),
                      NULLIF(TRIM(usu.primerApellido), N''), NULLIF(TRIM(usu.segundoApellido), N''))) > 0
               OR CHARINDEX(@busquedaFiltro, asg.nombre) > 0
               OR CHARINDEX(@busquedaFiltro, asg.codigo) > 0
               OR CHARINDEX(@busquedaFiltro, CAST(sra.justificacionSolicitud AS NVARCHAR(MAX))) > 0)
        ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
