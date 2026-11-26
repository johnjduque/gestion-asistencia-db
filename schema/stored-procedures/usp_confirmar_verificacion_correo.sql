USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: confirma la verificacion del correo. Consume el token (un solo uso) y marca Usuario.correoConfirmado = 1
-- en una unica transaccion con UPDLOCK/HOLDLOCK (dos confirmaciones simultaneas: solo una gana).
-- Publico sin ejecutor: la credencial es el hash del token. Cualquier token invalido (inexistente, vencido, usado,
-- revocado, nulo o de usuario inactivo) responde exactamente igual (VCE_002). Resultset canonico de 4 columnas.
-- SKILLS-BD lote 8 (2026-11-26): DECLARE del CATCH a la cabecera, PASO n, IF con BEGIN/END y usuario activo por uv_usuario (antes, la tabla). El bloqueo del token sigue en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_confirmar_verificacion_correo]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @consumidos TABLE (usuario UNIQUEIDENTIFIER NOT NULL);
    DECLARE @estadoTransaccionCatch INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- AUD-BD M-6: un error no capturado condena la transaccion; el CATCH ya maneja XACT_STATE() = -1 (THROW si no es propia)
    BEGIN TRY
        -- PASO 1: Transaccion propia, o savepoint si el llamador ya tiene una abierta
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_ident_confirmar;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Consumir el token vigente de un usuario activo (bloqueo UPDLOCK/HOLDLOCK sobre la tabla del token)
        UPDATE t
        SET t.fechaUsoUtc = SYSUTCDATETIME()
        OUTPUT inserted.usuario INTO @consumidos (usuario)
        FROM dbo.TokenVerificacionCorreo t WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.uv_usuario u ON u.id = t.usuario
        WHERE t.tokenHash = @tokenHash
          AND t.fechaUsoUtc IS NULL
          AND t.fechaRevocacionUtc IS NULL
          AND SYSUTCDATETIME() < t.fechaExpiracionUtc
          AND u.estaActivoUsuario = 1;

        -- PASO 3: Con token consumido, confirmar el correo (VCE_006); si no, rechazo VCE_002 sin escrituras
        IF EXISTS (SELECT 1 FROM @consumidos)
        BEGIN
            UPDATE u
            SET u.correoConfirmado = 1
            FROM dbo.Usuario u
            WHERE u.id IN (SELECT usuario FROM @consumidos);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VCE_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
        ELSE
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VCE_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: La rama de rechazo no escribe nada, por lo que no requiere ROLLBACK (ademas un ROLLBACK no es valido si el
        -- llamador usa INSERT ... EXEC). Solo se confirma la transaccion propia; con savepoint no hay nada que deshacer.
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
    END TRY
    BEGIN CATCH
        -- PASO 5: Revertir lo propio; con transaccion del llamador no confirmable relanza, si no responde SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_ident_confirmar;
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
