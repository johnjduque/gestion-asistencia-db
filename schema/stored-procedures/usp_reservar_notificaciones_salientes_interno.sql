USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reservar_notificaciones_salientes_interno]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Operacion atomica de reserva concurrente con READPAST y UPDLOCK.
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso) y PASO n; estados por uv_estado_notificacion (antes, la tabla). La reserva con UPDLOCK/READPAST sigue en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_reservar_notificaciones_salientes_interno]
(
    @lote          INT,
    @leaseSegundos INT,
    @instancia     NVARCHAR(100),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();
    DECLARE @reservadoHasta DATETIMEOFFSET(7) = DATEADD(SECOND, @leaseSegundos, @ahora);
    DECLARE @idPendiente    UNIQUEIDENTIFIER;
    DECLARE @idReservada    UNIQUEIDENTIFIER;
    DECLARE @idReintentable UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia BIT;
    DECLARE @savepointCreado BIT;
    DECLARE @errorMsg NVARCHAR(4000);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: Estados del outbox por codigo
    SELECT @idPendiente    = MAX(CASE WHEN codigo = 'PENDIENTE' THEN id END),
           @idReservada    = MAX(CASE WHEN codigo = 'RESERVADA' THEN id END),
           @idReintentable = MAX(CASE WHEN codigo = 'FALLIDA_REINTENTABLE' THEN id END)
    FROM dbo.uv_estado_notificacion;

    SET @transaccionPropia = 0;
    SET @savepointCreado = 0;

    BEGIN TRY
        -- PASO 2: Transaccion propia, o savepoint si el llamador ya tiene una abierta
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sv_reservar_notif_salientes;
            SET @savepointCreado = 1;
        END

        -- PASO 3: Reservar hasta @lote notificaciones listas (lectura con UPDLOCK/READPAST en la tabla) y devolverlas
        ;WITH Elegibles AS (
            SELECT TOP (@lote) id
            FROM dbo.NotificacionSaliente WITH (UPDLOCK, READPAST, ROWLOCK)
            WHERE (idEstado IN (@idPendiente, @idReintentable) AND proximoIntentoEn <= @ahora)
               OR (idEstado = @idReservada AND reservadoHasta < @ahora)
            ORDER BY creadoEn ASC
        )
        UPDATE n
        SET n.idEstado       = @idReservada,
            n.reservadoHasta = @reservadoHasta,
            n.reservadoPor   = @instancia,
            n.intentos       = n.intentos + 1
        OUTPUT
            inserted.id,
            inserted.tipo,
            inserted.asunto,
            inserted.mensaje,
            inserted.destinatarios,
            inserted.datos,
            inserted.intentos,
            inserted.creadoEn,
            inserted.idCorrelacion,
            inserted.traceId,
            inserted.spanId
        FROM dbo.NotificacionSaliente n
        INNER JOIN Elegibles e ON n.id = e.id;

        -- PASO 4: Confirmar la transaccion propia
        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: comando con resultset (las filas reservadas): revierte solo lo propio y relanza el error con el detalle
        -- tecnico (51000); la fachada no lo atrapa y el llamador lo traduce (comportamiento previo, sin triplete).
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_reservar_notif_salientes;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        SET @errorMsg = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        THROW 51000, @errorMsg, 1;
    END CATCH
END;
GO
