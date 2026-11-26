USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_depurar_notificaciones_salientes_interno]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Operacion atomica de eliminacion de notificaciones terminales vencidas.
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso) y PASO n; candidatas por uv_notificacion_saliente (antes, la tabla). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_depurar_notificaciones_salientes_interno]
(
    @retencionDias           INT,
    @lote                    INT,
    @idEstadoEntregada       UNIQUEIDENTIFIER,
    @idEstadoDefinitiva      UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @eliminadas              INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @limite DATETIMEOFFSET(7);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @eliminadas = 0;
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
            SAVE TRANSACTION sv_depurar_notif_salientes;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Eliminar hasta @lote notificaciones terminales (ENTREGADA o FALLIDA_DEFINITIVA) creadas antes de la retencion
        SET @limite = DATEADD(DAY, -@retencionDias, SYSUTCDATETIME());

        ;WITH Elegibles AS (
            SELECT TOP (@lote) id
            FROM dbo.uv_notificacion_saliente
            WHERE idEstado IN (@idEstadoEntregada, @idEstadoDefinitiva)
              AND creadoEn < @limite
            ORDER BY creadoEn ASC
        )
        DELETE FROM dbo.NotificacionSaliente
        WHERE id IN (SELECT id FROM Elegibles);

        SET @eliminadas = @@ROWCOUNT;

        -- PASO 3: Mensaje de exito del catalogo
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_005',
            @p_param1 = 'Notificaciones Salientes',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Eliminadas: ', @eliminadas, '. Correlacion: ', @idCorrelacionDefecto);

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
            ROLLBACK TRANSACTION sv_depurar_notif_salientes;
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
