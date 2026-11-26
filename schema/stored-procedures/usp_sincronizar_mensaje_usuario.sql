USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_sincronizar_mensaje_usuario (INT-003, migracion 45)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema con tupla canonica + codigo, huboCambio y
-- fechaModificacion (NULL si estadoResultado = 0) + existeMensaje (1/0 cuando se busco la fila; NULL si un rechazo previo
-- impidio buscarla). Con existeMensaje = 0 el backend distingue "codigo ajeno a la BD" de un fallo real.
--
-- Copia en dbo.CatalogoMensajeUsuario el texto vigente de un mensaje de usuario que cambio en MessageUcoLab (componente de
-- mensajes del equipo de mensajeria). Lo invoca el backend al recibir el aviso de Pulsar (MessageCreated/MessageUpdated) o
-- en la reconciliacion completa (arranque y MessagesChanged), despues de leer el texto con su identidad de servicio. No hay
-- usuario ejecutor: es un proceso del sistema, por eso no valida RBAC.
--
-- Pasos: correlacion -> codigo obligatorio (GEN_002) -> contenido obligatorio (GEN_002) -> transaccion y fila bloqueada
-- por codigo (UPDLOCK, HOLDLOCK) -> la fila debe existir (GEN_001: la BD solo refleja codigos de su propio catalogo; un
-- codigo nuevo en MessageUcoLab no crea filas) -> texto igual en comparacion binaria: exito sin escritura (huboCambio = 0)
-- -> UPDATE contenido y fechaModificacion. No cambia estaActivo, tipoMensaje ni severidad. El exito es GEN_005.
-- Transaccion propia o SAVE TRANSACTION. Las ramas de rechazo no escriben.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_mensaje_usuario]
(
    @codigo        VARCHAR(100),
    @contenido     NVARCHAR(4000),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @codigoLimpio     VARCHAR(100) = TRIM(@codigo);
    DECLARE @contenidoLimpio  NVARCHAR(4000) = TRIM(@contenido);
    DECLARE @idMensaje        UNIQUEIDENTIFIER = NULL;
    DECLARE @contenidoActual  NVARCHAR(4000);
    DECLARE @fechaNueva       DATETIME = NULL;
    DECLARE @huboCambio       BIT = 0;
    DECLARE @existeMensaje    BIT = NULL;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: codigo y contenido obligatorios (GEN_002)
        IF @estadoResultado = 1 AND (@codigoLimpio IS NULL OR @codigoLimpio = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'codigo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@contenidoLimpio IS NULL OR @contenidoLimpio = N'')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'contenido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: transaccion y evaluacion bajo el bloqueo de la fila del mensaje
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_sincronizar_mensaje_usuario;
                SET @savepointCreado = 1;
            END

            SELECT @idMensaje = m.id, @contenidoActual = m.contenido, @fechaNueva = m.fechaModificacion
            FROM dbo.CatalogoMensajeUsuario m WITH (UPDLOCK, HOLDLOCK)
            WHERE m.codigo = @codigoLimpio;

            SET @existeMensaje = IIF(@idMensaje IS NULL, 0, 1);

            IF @idMensaje IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'CatalogoMensajeUsuario',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Codigo: ', @codigoLimpio,
                                                      ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
                SET @fechaNueva = NULL;
            END
            ELSE
            BEGIN
                IF @contenidoLimpio COLLATE Latin1_General_BIN2 <> @contenidoActual COLLATE Latin1_General_BIN2
                BEGIN
                    UPDATE dbo.CatalogoMensajeUsuario
                    SET contenido = @contenidoLimpio, fechaModificacion = SYSUTCDATETIME()
                    WHERE id = @idMensaje;

                    SELECT @fechaNueva = fechaModificacion FROM dbo.CatalogoMensajeUsuario WHERE id = @idMensaje;
                    SET @huboCambio = 1;
                END

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Mensaje',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Codigo: ', @codigoLimpio,
                                                      ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_sincronizar_mensaje_usuario;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @huboCambio = 0;
        SET @fechaNueva = NULL;
        SET @existeMensaje = NULL;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        codigo                  = IIF(@estadoResultado = 1, @codigoLimpio, NULL),
        huboCambio              = IIF(@estadoResultado = 1, @huboCambio, NULL),
        fechaModificacion       = IIF(@estadoResultado = 1, @fechaNueva, NULL),
        existeMensaje           = @existeMensaje;
END;
GO
