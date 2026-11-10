USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_aprobar_solicitud_sesion (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idSesion, idGrupo, fechaHoraInicio, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa aprueba la solicitud de una sesion extraordinaria creada por el docente. Reglas:
--   * RBAC COORDINADOR (SEC_001); sesion existente (SES_001); ambito = programa del grupo INTERSECT programas del coordinador
--     (SEC_002) - usp_validar_coordinador_sesion_interno;
--   * observacion opcional recortada <= SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA (SES_021);
--   * la sesion debe tener una solicitud (SES_025), en estado en espera (SES_024 si ya fue resuelta) y no estar cancelada (SES_011);
--   * la solicitud pasa al estado final con esAprobada = 1 (catalogo EstadoSolicitudSesion), con usuario, fecha y observacion.
--     Desde ese momento la sesion admite tomas y asistencia, y los estudiantes la ven. El aviso a los estudiantes y al docente lo
--     publica el backend (usp_consultar_destinatarios_solicitud_sesion).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la solicitud.
-- Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_aprobar_solicitud_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @observacion       NVARCHAR(500) = NULL,
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

    DECLARE @observacionLimpia NVARCHAR(500) = NULLIF(LTRIM(RTRIM(@observacion)), N'');
    DECLARE @observacionMaxima INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA');
    DECLARE @observacionMaximaTexto NVARCHAR(20);
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraInicio   DATETIME2;
    DECLARE @existeSolicitud   BIT = 0;
    DECLARE @solicitudFinal    BIT = 0;
    DECLARE @idEstadoAprobada  UNIQUEIDENTIFIER;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASOS 1-4: correlacion, ejecutor, RBAC COORDINADOR, sesion existente y ambito (compartido)
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;

        -- PASO 5: observacion recortada dentro del maximo parametrizado (SES_021)
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

        -- PASO 6: estado final de aprobacion del catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoAprobada = e.id
            FROM dbo.uv_estado_solicitud_sesion e
            WHERE e.esFinal = 1 AND e.esAprobada = 1
            ORDER BY e.orden;

            IF @idEstadoAprobada IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'EstadoSolicitudSesion(esFinal = 1, esAprobada = 1)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_aprobar_solicitud_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @fechaHoraInicio = s.fechaHoraInicio
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            SELECT @existeSolicitud = 1, @solicitudFinal = e.esFinal
            FROM dbo.SesionSolicitud ss
            INNER JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
            WHERE ss.sesion = @idSesionDefecto;

            IF @existeSolicitud = 0
                SET @codigoRechazo = 'SES_025';
            ELSE IF @solicitudFinal = 1
                SET @codigoRechazo = 'SES_024';
            ELSE IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.SesionSolicitud
                SET idEstado = @idEstadoAprobada,
                    usuarioResolucion = @idUsuarioEjecutorDefecto,
                    fechaResolucionUtc = SYSUTCDATETIME(),
                    observacion = @observacionLimpia
                WHERE sesion = @idSesionDefecto;

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_026', @p_param1 = @idSesionDefecto,
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
            ROLLBACK TRANSACTION sp_aprobar_solicitud_sesion;

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
        fechaHoraInicio         = IIF(@estadoResultado = 1, @fechaHoraInicio, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
