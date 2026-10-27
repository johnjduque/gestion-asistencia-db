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
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @eliminadas = 0;
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
            SAVE TRANSACTION sv_depurar_notif_salientes;
            SET @savepointCreado = 1;
        END

        DECLARE @limite DATETIMEOFFSET(7) = DATEADD(DAY, -@retencionDias, SYSUTCDATETIME());

        ;WITH Elegibles AS (
            SELECT TOP (@lote) id
            FROM dbo.NotificacionSaliente
            WHERE idEstado IN (@idEstadoEntregada, @idEstadoDefinitiva)
              AND creadoEn < @limite
            ORDER BY creadoEn ASC
        )
        DELETE FROM dbo.NotificacionSaliente
        WHERE id IN (SELECT id FROM Elegibles);

        SET @eliminadas = @@ROWCOUNT;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_005',
            @p_param1 = 'Notificaciones Salientes',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Eliminadas: ', @eliminadas, '. Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
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
