-- ============================================================================
-- MIGRACION UP 34: validaciones compartidas de sesion (sin cambio funcional; quita codigo duplicado)
-- Crea usp_validar_docente_titular_sesion_interno (correlacion, ejecutor y sesion obligatorios, RBAC DOCENTE y titularidad SESION) y lo usan
-- usp_consultar_destinatarios_sesion_cancelada y usp_consultar_destinatarios_sesion_manual. usp_cancelar_sesion_coordinador pasa a usar
-- usp_validar_coordinador_sesion_interno (migracion 30) en lugar de repetir sus cuatro pasos. No cambia firmas, columnas, mensajes ni permisos:
-- el interno nuevo no se concede al rol runtime (encadenamiento de propiedad). Idempotente. Down: 34_deduplicar_validaciones_sesion_down.sql.
-- ============================================================================
PRINT 'MIGRACION 34 UP: validaciones compartidas de sesion';
GO
-- ---- schema/stored-procedures/usp_validar_docente_titular_sesion_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_docente_titular_sesion_interno (CULM-001; HU047)
--
-- Validacion compartida por las consultas de destinatarios que hace el docente sobre una sesion suya
-- (usp_consultar_destinatarios_sesion_cancelada y usp_consultar_destinatarios_sesion_manual). Mantiene en un unico punto:
--   * correlacion presente;
--   * ejecutor y sesion obligatorios (GEN_002);
--   * RBAC DOCENTE (SEC_001);
--   * titularidad jerarquica del docente sobre la sesion (tipo 'SESION').
-- No escribe, no abre transacciones y no lanza: devuelve el resultado en los parametros de salida y el llamador decide
-- (las consultas de lectura lanzan THROW 51000 con el mensaje tecnico). No se concede al rol runtime: se usa por
-- encadenamiento de propiedad desde los SP publicos.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_titular_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @correlacion UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @docente     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @sesion      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @correlacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idSesion IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @correlacion);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @docente,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @correlacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @docente,
            @idEntidadPadre = @sesion,
            @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @correlacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_destinatarios_sesion_cancelada.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_cancelada (CULM-001 B.1, HU047; CONTRACT §2.7.3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo).
-- Destinatarios de la notificacion SESION_CANCELADA: las matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo de
-- la sesion, solo si la sesion esta cancelada (si no, 0 filas). RBAC DOCENTE + titularidad 'SESION' dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Mismo formato que usp_consultar_destinatarios_reclamo_asistencia: el
-- correo es de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_cancelada]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;

    -- Correlacion, ejecutor y sesion obligatorios, RBAC DOCENTE y titularidad 'SESION' (validacion compartida)
    EXEC dbo.usp_validar_docente_titular_sesion_interno
        @idSesion = @idSesion,
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idEstudiante      = eg.idEstudiante,
        idUsuario         = ei.idUsuario,
        nombreCompleto    = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correo            = u.correo,
        nombreAsignatura  = g.nombreAsignatura,
        nombreGrupo       = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
        nombreDocente     = CAST(di.nombreCompleto AS NVARCHAR(400)),
        fechaHoraInicio   = se.fechaHoraInicio,
        fechaHoraFin      = se.fechaHoraFin,
        motivoCancelacion = se.motivoCancelacion
    FROM dbo.uv_sesion_estado se
    INNER JOIN dbo.uv_grupo g               ON g.id = se.idGrupo
    INNER JOIN dbo.uv_docente_identidad di  ON di.id = g.idDocente
    INNER JOIN dbo.uv_estudiante_grupo eg   ON eg.idGrupo = se.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
    INNER JOIN dbo.uv_usuario u             ON u.id = ei.idUsuario
    WHERE se.idSesion = @idSesionDefecto
      AND se.estaCancelada = 1
    ORDER BY ei.nombreCompleto, eg.idEstudiante;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_destinatarios_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_manual (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + coordinadores).
-- Destinatarios del aviso de una sesion creada manualmente por el docente (uv_sesion_manual; una sesion no manual devuelve 0 filas):
--   * ESTUDIANTE:  matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo;
--   * COORDINADOR: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo). Un coordinador de dos
--                  programas del mismo grupo es UNA fila; un grupo mixto devuelve ambos coordinadores.
-- CULM-001 / DEC-065 (2): ademas devuelve la fila del DOCENTE titular (tipoDestinatario = 'DOCENTE', al final del orden) para que el backend
-- le avise la decision del coordinador; el aviso a la coordinacion al crear lo sigue dando la fila COORDINADOR.
-- Ambito: RBAC DOCENTE + titularidad 'SESION' dentro del SP (THROW 51000 con el mensaje tecnico si falla). El correo es de uso
-- interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs. Mismo formato que
-- usp_consultar_destinatarios_sesion_cancelada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_manual]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;

    -- Correlacion, ejecutor y sesion obligatorios, RBAC DOCENTE y titularidad 'SESION' (validacion compartida)
    EXEC dbo.usp_validar_docente_titular_sesion_interno
        @idSesion = @idSesion,
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  tipoDestinatario = x.tipoDestinatario,
            idUsuario        = x.idUsuario,
            nombreCompleto   = x.nombreCompleto,
            correo           = x.correo,
            nombreAsignatura = x.nombreAsignatura,
            nombreGrupo      = x.nombreGrupo,
            nombreDocente    = x.nombreDocente,
            fechaHoraInicio  = x.fechaHoraInicio,
            fechaHoraFin     = x.fechaHoraFin
    FROM (
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = u.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g                 ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = sm.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario u               ON u.id = ei.idUsuario
        WHERE sm.idSesion = @idSesionDefecto

        UNION ALL

        SELECT  tipoDestinatario = CAST(N'COORDINADOR' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ci.idUsuario,
                nombreCompleto   = CAST(ci.nombreCompleto AS NVARCHAR(400)),
                correo           = ci.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        INNER JOIN (
            SELECT DISTINCT ci2.idUsuario, ci2.nombreCompleto, ci2.correo
            FROM dbo.ufn_programas_grupo(
                     (SELECT s.idGrupo FROM dbo.uv_sesion_manual s WHERE s.idSesion = @idSesionDefecto)) pg
            INNER JOIN dbo.Programa p                    ON p.id = pg.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad ci2  ON ci2.id = p.coordinador
                                                        AND ci2.estaActivoRolCoordinador = 1 AND ci2.estaActivoUsuario = 1
        ) ci ON 1 = 1
        WHERE sm.idSesion = @idSesionDefecto
        UNION ALL
        SELECT  tipoDestinatario = CAST(N'DOCENTE' AS NVARCHAR(20)),
                ordenTipo        = 3,
                idUsuario        = di.idUsuario,
                nombreCompleto   = CAST(di.nombreCompleto AS NVARCHAR(400)),
                correo           = ud.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
        WHERE sm.idSesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
-- ---- schema/stored-procedures/usp_cancelar_sesion_coordinador.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cancelar_sesion_coordinador (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la misma tupla que usp_cancelar_sesion: canonica + idSesion, idGrupo,
-- fechaCancelacionUtc, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa cancela una sesion creada manualmente por el docente (uv_sesion_manual: procedencia NULL de v1 o UTC_V2 de v2).
-- No cambia la firma publica de usp_cancelar_sesion (docente). Reglas:
--   * RBAC COORDINADOR (SEC_001); sesion existente (SES_001);
--   * ambito: el coordinador coordina AL MENOS UNO de los programas vigentes del grupo (ufn_programas_grupo INTERSECT
--     ufn_programas_coordinador); si no, SEC_002. En un grupo mixto lo reciben (y pueden cancelar) los coordinadores de ambos programas;
--   * solo sesiones manuales: SES_018; motivo del catalogo MotivoCancelacionSesion activo: SES_019; observacion recortada <=
--     SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA: SES_021;
--   * mismas reglas de escritura que usp_cancelar_sesion: doble cancelacion SES_011 (se conserva el motivo original); con asistencia o
--     toma SES_012 (ventana vigente) o SES_016 (terminada);
--   * SesionCancelacion.motivo = nombre del motivo [+ ': ' + observacion]; tipo = el manual (TipoCancelacionSesion.esAutomatica = 0);
--     usuarioEjecutor = el coordinador (auditoria). Evento y aviso a estudiantes los publica el backend (SESION_CANCELADA).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la cancelacion y la
-- asistencia. Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cancelar_sesion_coordinador]
(
    @idSesion          UNIQUEIDENTIFIER,
    @codigoMotivo      NVARCHAR(50),
    @observacion       NVARCHAR(4000) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @observacionLimpia NVARCHAR(4000) = NULLIF(LTRIM(RTRIM(@observacion)), N'');
    DECLARE @observacionMaxima INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @codigoTipoManual  NVARCHAR(20);
    DECLARE @nombreMotivo      NVARCHAR(200);
    DECLARE @motivoTexto       NVARCHAR(500);
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraFin      DATETIME2;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
    DECLARE @observacionMaximaTexto NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASOS 1 a 4: correlacion, ejecutor obligatorio, RBAC COORDINADOR (SEC_001), sesion existente (SES_001) y ambito del
        -- coordinador sobre el grupo de la sesion (SEC_002): validacion compartida con las demas operaciones del coordinador.
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;

        -- PASO 5: solo sesiones creadas manualmente por el docente (SES_018)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_manual sm WHERE sm.idSesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_018', @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: motivo del catalogo (SES_019)
        IF @estadoResultado = 1
        BEGIN
            SELECT @nombreMotivo = m.nombre
            FROM dbo.uv_motivo_cancelacion_sesion m
            WHERE m.codigo = LTRIM(RTRIM(@codigoMotivo)) AND m.estaActivo = 1;

            IF @nombreMotivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_019', @p_param1 = @codigoMotivo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: observacion recortada dentro del maximo parametrizado (SES_021)
        IF @estadoResultado = 1
           AND (@observacionMaxima IS NULL OR LEN(@observacionLimpia) > @observacionMaxima)
        BEGIN
            SET @observacionMaximaTexto = CONVERT(NVARCHAR(20), @observacionMaxima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_021', @p_param1 = @observacionMaximaTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 8: tipo manual de cancelacion por bandera de catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id, @codigoTipoManual = t.codigo
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            IF @idTipoManual IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 9: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cancelar_sesion_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT @fechaHoraFin = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';
            ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = @idSesionDefecto)
                 OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesionDefecto)
                SET @codigoRechazo = IIF(SYSUTCDATETIME() >= DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), @fechaHoraFin),
                                         'SES_016', 'SES_012');

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();
                SET @motivoTexto = IIF(@observacionLimpia IS NULL, @nombreMotivo, CONCAT(@nombreMotivo, N': ', @observacionLimpia));

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoTexto, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_020', @p_param1 = @idSesionDefecto, @p_param2 = @codigoTipoManual,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera el bloqueo).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
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
            ROLLBACK TRANSACTION sp_cancelar_sesion_coordinador;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSesion                = IIF(@estadoResultado = 1, @idSesionDefecto, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCancelacionUtc     = IIF(@estadoResultado = 1, @fechaCancelacion, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
PRINT 'MIGRACION 34 UP OK';
GO
