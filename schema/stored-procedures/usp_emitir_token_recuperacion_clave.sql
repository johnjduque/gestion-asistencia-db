USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_emitir_token_recuperacion_clave (HU177)
--
-- Registra el enlace de un solo uso para definir una contrasena nueva (solo recibe y guarda su SHA-256). Lo invoca el
-- canal de correo al entregar el aviso. Revoca el enlace pendiente anterior del usuario; la vigencia es ahora +
-- RECUPERACION_CLAVE/TTL_MINUTOS. Tecnico (sin ejecutor): la credencial es la identidad del proceso de entrega.
-- Rechaza con VCE_007 si el usuario no existe o no esta activo. Resultset canonico de 4 columnas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_emitir_token_recuperacion_clave]
(
    @idUsuario     UNIQUEIDENTIFIER,
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoMensaje   VARCHAR(20) = NULL;
    DECLARE @parametroMensaje NVARCHAR(200) = NULL;
    DECLARE @abrioTransaccion BIT = 0;
    DECLARE @vigenciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'TTL_MINUTOS');
    DECLARE @emisionUtc      DATETIME2(0) = SYSUTCDATETIME();
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @idUsuario IS NULL OR @tokenHash IS NULL
                SELECT @codigoMensaje = 'GEN_002', @parametroMensaje = N'idUsuario/tokenHash';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuario AND u.estado = 1)
                SET @codigoMensaje = 'VCE_007';
            ELSE IF @vigenciaMinutos IS NULL OR @vigenciaMinutos < 1
                SELECT @codigoMensaje = 'GEN_002', @parametroMensaje = N'RECUPERACION_CLAVE/TTL_MINUTOS';

            IF @codigoMensaje IS NULL
            BEGIN
                -- Revoca el enlace pendiente e inserta el nuevo como una sola unidad (un pendiente por usuario).
                IF @@TRANCOUNT = 0
                BEGIN
                    BEGIN TRANSACTION;
                    SET @abrioTransaccion = 1;
                END

                UPDATE p
                SET p.fechaRevocacionUtc = @emisionUtc
                FROM dbo.TokenRecuperacionClave p WITH (UPDLOCK, HOLDLOCK)
                WHERE p.usuario = @idUsuario AND p.fechaUsoUtc IS NULL AND p.fechaRevocacionUtc IS NULL;

                INSERT INTO dbo.TokenRecuperacionClave (usuario, tokenHash, fechaEmisionUtc, fechaExpiracionUtc)
                VALUES (@idUsuario, @tokenHash, @emisionUtc, DATEADD(MINUTE, @vigenciaMinutos, @emisionUtc));

                IF @abrioTransaccion = 1
                    COMMIT TRANSACTION;

                SELECT @codigoMensaje = 'GEN_004', @parametroMensaje = N'Enlace de recuperacion de contrasena';
            END
            ELSE
                SET @estadoResultado = 0;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoMensaje, @p_param1 = @parametroMensaje,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        IF @abrioTransaccion = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        IF @abrioTransaccion = 0 AND XACT_STATE() = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion           = @idCorrelacionDefecto,
           mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado,
           estadoResultado         = @estadoResultado;
END;
GO
