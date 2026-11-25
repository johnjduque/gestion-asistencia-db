USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121/HU122 (habilitador compartido con IAM-001): cambia Usuario.estado. Idempotente: si ya tiene el estado
-- destino no modifica nada y responde exito. Sin transaccion propia (corre dentro de la fachada publica).
-- SKILLS-BD lote 3 (2026-11-25): PASO n y correlacion por defecto en los mensajes; mismo comportamiento.
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @estaActivo              BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: usuario y estado obligatorios (GEN_002), usuario existente (GEN_001)
        IF @idUsuario IS NULL OR @estaActivo IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @idUsuario)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        ELSE
        BEGIN
            -- PASO 3: cambio de estado (idempotente)
            UPDATE dbo.Usuario SET estado = @estaActivo WHERE id = @idUsuario AND estado <> @estaActivo;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: error no controlado (SYS_001). Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
