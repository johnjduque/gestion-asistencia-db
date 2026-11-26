USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_registrar_notificacion_saliente_interno]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Operacion atomica de persistencia interna.
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso) y PASO n. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_notificacion_saliente_interno]
(
    @tipo                    VARCHAR(60),
    @asunto                  NVARCHAR(200),
    @mensaje                 NVARCHAR(4000),
    @destinatariosJson       NVARCHAR(MAX),
    @datosJson               NVARCHAR(MAX),
    @idEstadoPendiente       UNIQUEIDENTIFIER,
    @traceId                 CHAR(32),
    @spanId                  CHAR(16),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @ahora DATETIMEOFFSET(7);
    DECLARE @idNotificacion UNIQUEIDENTIFIER;
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
            SAVE TRANSACTION sv_registrar_notif_saliente;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Insertar la notificacion en estado PENDIENTE, lista para el primer intento
        SET @ahora = SYSUTCDATETIME();
        SET @idNotificacion = NEWID();

        INSERT INTO dbo.NotificacionSaliente (
            id, tipo, asunto, mensaje, destinatarios, datos, idEstado,
            intentos, creadoEn, proximoIntentoEn, idCorrelacion, traceId, spanId
        )
        VALUES (
            @idNotificacion, @tipo, @asunto, @mensaje, @destinatariosJson, @datosJson, @idEstadoPendiente,
            0, @ahora, @ahora, @idCorrelacionDefecto, @traceId, @spanId
        );

        -- PASO 3: Mensaje de exito del catalogo
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_004',
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
            ROLLBACK TRANSACTION sv_registrar_notif_saliente;
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
