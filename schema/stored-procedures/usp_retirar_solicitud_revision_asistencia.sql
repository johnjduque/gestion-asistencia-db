USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_solicitud_revision_asistencia (CULM-001 A.2-7; F-EST-003; CONTRACT §8.2.3 A2-DB-3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE retira su propio reclamo (solicitud de revision de asistencia) mientras esta pendiente:
--   * RBAC ESTUDIANTE (SEC_001). Ambito dentro del SP: el reclamo debe ser del ejecutor
--     (asistencia -> EstudianteGrupo -> Estudiante.usuario); inexistente o ajeno => REV_006 (no revela que existe).
--   * Bajo UPDLOCK, HOLDLOCK su estado debe ser el codigo de RECLAMO/ESTADO_PENDIENTE; si no (ya resuelto o retirado),
--     REV_007. Pasa al estado con el codigo de RECLAMO/ESTADO_RETIRADO (X "retirada", A2-C4). Exito REV_008.
--   * El soporte (ArchivoSoporte) se conserva (almacenamiento WORM y auditoria). Sin notificacion.
-- SET XACT_ABORT ON; transaccion propia o savepoint; un rechazo de negocio no escribe ni hace ROLLBACK.
-- VAL-pendientes-john PRU-15: un reclamo pendiente de una sesion de un periodo cerrado por el cierre masivo ya no se retira (PER_008,
-- despues de la propiedad y del estado, sin escrituras).
-- ============================================================================
-- SKILLS-BD lote 11 (2026-11-26): IF con BEGIN/END, PASO en el CATCH y lecturas sin bloqueo por vistas uv_* (antes, las tablas).
-- La lectura con UPDLOCK, HOLDLOCK de dbo.SolicitudRevisionAsistencia y la escritura siguen en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_solicitud_revision_asistencia]
(
    @idSolicitudRevision UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idUsuarioEjecutor   UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPendiente      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(10));
    DECLARE @codigoRetirado       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(10));
    DECLARE @idEstadoRetirado     UNIQUEIDENTIFIER;
    DECLARE @idSolicitudBloqueada UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoActual   NVARCHAR(10);
    DECLARE @idSesionSolicitud    UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(20) = NULL;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: estados por catalogo (parametros RECLAMO/*)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoRetirado = e.id FROM dbo.uv_estado e WHERE e.codigo = @codigoRetirado;
            IF @idEstadoRetirado IS NULL OR @codigoPendiente IS NULL OR @codigoPendiente = N''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'Estado de reclamo (RECLAMO/ESTADO_*)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: transaccion, propiedad y estado bajo bloqueo
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
                SAVE TRANSACTION sp_retirar_solicitud_revision;
                SET @savepointCreado = 1;
            END

            SELECT @idSolicitudBloqueada = r.id, @codigoEstadoActual = est.codigo, @idSesionSolicitud = a.idSesion
            FROM dbo.SolicitudRevisionAsistencia r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.uv_estado est ON est.id = r.estado
            INNER JOIN dbo.uv_asistencia_registro a ON a.id = r.asistencia
            INNER JOIN dbo.uv_estudiante_grupo_registro eg ON eg.id = a.idEstudianteGrupo
            INNER JOIN dbo.uv_estudiante_identidad e ON e.id = eg.idEstudiante
            WHERE r.id = @idSolicitudRevision
              AND e.idUsuario = @idUsuarioEjecutor;

            IF @idSolicitudBloqueada IS NULL
            BEGIN
                SET @codigoRechazo = 'REV_006';
            END
            ELSE IF @codigoEstadoActual <> @codigoPendiente
            BEGIN
                SET @codigoRechazo = 'REV_007';
            END
            ELSE
            BEGIN
                -- VAL-pendientes-john PRU-15: periodo cerrado por el cierre masivo => PER_008 (sin escrituras)
                EXEC dbo.usp_validar_periodo_abierto_sesion_interno
                    @idSesion = @idSesionSolicitud,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @idSolicitudBloqueada IS NOT NULL AND @codigoRechazo IS NULL AND @estadoResultado = 1
            BEGIN
                UPDATE dbo.SolicitudRevisionAsistencia
                SET estado = @idEstadoRetirado
                WHERE id = @idSolicitudBloqueada;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_008', @p_param1 = @idSolicitudBloqueada,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END

        -- PASO 5: mensaje de rechazo por catalogo (sin escrituras)
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @idSolicitudRevision,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 6: error: revertir lo propio, relanzar si la transaccion externa quedo condenada; si no, SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_retirar_solicitud_revision;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

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
        estadoResultado         = @estadoResultado;
END;
GO
