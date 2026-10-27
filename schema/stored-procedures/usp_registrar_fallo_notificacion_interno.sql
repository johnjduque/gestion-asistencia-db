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
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
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

        DECLARE @intentosActuales INT;
        SELECT @intentosActuales = intentos FROM dbo.NotificacionSaliente WHERE id = @id;

        DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();
        DECLARE @nuevoEstado UNIQUEIDENTIFIER;
        DECLARE @nuevoProximoIntento DATETIMEOFFSET(7) = NULL;

        IF @reintentable = 0 OR @intentosActuales >= @maxIntentos
        BEGIN
            SET @nuevoEstado = @idEstadoDefinitiva;
            SET @nuevoProximoIntento = NULL;
        END
        ELSE
        BEGIN
            SET @nuevoEstado = @idEstadoReintentable;

            -- Calculo: MIN(base * 2^(intentos - 1), max)
            DECLARE @exp INT = IIF(@intentosActuales - 1 < 0, 0, IIF(@intentosActuales - 1 > 30, 30, @intentosActuales - 1));
            DECLARE @delaySegundos BIGINT = CAST(@backoffBaseSegundos AS BIGINT) * POWER(CAST(2 AS BIGINT), @exp);
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

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_005',
            @p_param1 = 'Notificacion Saliente',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
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
