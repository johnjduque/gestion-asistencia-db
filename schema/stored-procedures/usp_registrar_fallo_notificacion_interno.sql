USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_registrar_fallo_notificacion_interno]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Operacion atomica de registro de fallo y calculo de backoff.
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso) y PASO n; intentos por uv_notificacion_saliente (antes, la tabla). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_fallo_notificacion_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @codigoError             VARCHAR(40),
    @detalleError            NVARCHAR(300),
    @reintentable            BIT,
    @maxIntentos             INT,
    @backoffBaseSegundos     INT,
    @backoffMaxSegundos      INT,
    @idEstadoReintentable    UNIQUEIDENTIFIER,
    @idEstadoDefinitiva      UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @intentosActuales INT;
    DECLARE @ahora DATETIMEOFFSET(7);
    DECLARE @nuevoEstado UNIQUEIDENTIFIER;
    DECLARE @nuevoProximoIntento DATETIMEOFFSET(7);
    DECLARE @exp INT;
    DECLARE @delaySegundos BIGINT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: Transaccion propia, o savepoint si el llamador ya tiene una abierta
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sv_registrar_fallo_notif;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Calcular el nuevo estado (reintentable con backoff exponencial o definitiva) y actualizar la notificacion
        SELECT @intentosActuales = intentos FROM dbo.uv_notificacion_saliente WHERE id = @id;

        SET @ahora = SYSUTCDATETIME();
        SET @nuevoProximoIntento = NULL;

        IF @reintentable = 0 OR @intentosActuales >= @maxIntentos
        BEGIN
            SET @nuevoEstado = @idEstadoDefinitiva;
            SET @nuevoProximoIntento = NULL;
        END
        ELSE
        BEGIN
            SET @nuevoEstado = @idEstadoReintentable;

            -- Calculo: MIN(base * 2^(intentos - 1), max)
            SET @exp = IIF(@intentosActuales - 1 < 0, 0, IIF(@intentosActuales - 1 > 30, 30, @intentosActuales - 1));
            SET @delaySegundos = CAST(@backoffBaseSegundos AS BIGINT) * POWER(CAST(2 AS BIGINT), @exp);
            IF @delaySegundos > @backoffMaxSegundos
            BEGIN
                SET @delaySegundos = @backoffMaxSegundos;
            END

            SET @nuevoProximoIntento = DATEADD(SECOND, @delaySegundos, @ahora);
        END

        UPDATE dbo.NotificacionSaliente
        SET idEstado         = @nuevoEstado,
            proximoIntentoEn = @nuevoProximoIntento,
            reservadoHasta   = NULL,
            reservadoPor     = NULL,
            codigoError      = @codigoError,
            detalleError     = @detalleError
        WHERE id = @id;

        -- PASO 3: Mensaje de exito del catalogo
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_005',
            @p_param1 = 'Notificacion Saliente',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

        -- PASO 4: Confirmar la transaccion propia
        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: Revertir solo lo propio (savepoint o transaccion) y responder SYS_001 (comportamiento previo)
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_registrar_fallo_notif;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
