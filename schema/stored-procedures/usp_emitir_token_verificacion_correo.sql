USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: emite el token de verificacion de correo (solo se recibe y guarda su SHA-256). Lo invoca el canal de
-- correo al entregar el aviso. Revoca el token activo previo del usuario y la vigencia es ahora + TTL_HORAS (parametro).
-- Tecnico (sin ejecutor): la credencial es la identidad del proceso de entrega. Resultset canonico de 4 columnas.
CREATE OR ALTER PROCEDURE [dbo].[usp_emitir_token_verificacion_correo]
(
    @idUsuario     UNIQUEIDENTIFIER,
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

    DECLARE @estadoUsuario     BIT;
    DECLARE @correoConfirmado  BIT;
    DECLARE @ttlHoras          INT;
    DECLARE @ahoraUtc          DATETIME2(0);
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: parametros obligatorios
        IF @estadoResultado = 1 AND (@idUsuario IS NULL OR @tokenHash IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuario/tokenHash',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: el usuario debe existir, estar activo y no tener el correo verificado
        IF @estadoResultado = 1
        BEGIN
            SELECT @estadoUsuario = u.estado, @correoConfirmado = u.correoConfirmado
            FROM dbo.Usuario u
            WHERE u.id = @idUsuario;

            IF @estadoUsuario IS NULL OR @estadoUsuario = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VCE_007',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @correoConfirmado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VCE_005',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: transaccion (propia o savepoint) y emision atomica: revoca el activo previo e inserta el nuevo
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
                SAVE TRANSACTION sp_ident_emitir_token;
                SET @savepointCreado = 1;
            END

            SET @ttlHoras = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'TTL_HORAS');
            SET @ahoraUtc = SYSUTCDATETIME();

            UPDATE t
            SET t.fechaRevocacionUtc = @ahoraUtc
            FROM dbo.TokenVerificacionCorreo t WITH (UPDLOCK, HOLDLOCK)
            WHERE t.usuario = @idUsuario AND t.fechaUsoUtc IS NULL AND t.fechaRevocacionUtc IS NULL;

            INSERT INTO dbo.TokenVerificacionCorreo (id, usuario, tokenHash, fechaEmisionUtc, fechaExpiracionUtc, fechaUsoUtc, fechaRevocacionUtc)
            VALUES (NEWID(), @idUsuario, @tokenHash, @ahoraUtc, DATEADD(HOUR, @ttlHoras, @ahoraUtc), NULL, NULL);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004', @p_param1 = 'Token de verificacion de correo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 5: cierre respetando ownership
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION sp_ident_emitir_token;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_ident_emitir_token;

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
        estadoResultado         = @estadoResultado;
END;
GO
