USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_depurar_notificaciones_salientes]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Fachada publica tecnica para purga de notificaciones terminales vencidas.
-- Salida Canonica + eliminadas: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado, eliminadas)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_depurar_notificaciones_salientes]
(
    @retencionDias INT              = 30,
    @lote          INT              = 1000,
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @eliminadas              INT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar retencionDias (1..3650)
        IF @estadoResultado = 1 AND (@retencionDias IS NULL OR @retencionDias < 1 OR @retencionDias > 3650)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Retencion fuera de rango (1-3650 dias). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar lote (1..5000)
        IF @estadoResultado = 1 AND (@lote IS NULL OR @lote < 1 OR @lote > 5000)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Lote fuera de rango (1-5000). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 4. Delegar al interno
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idEntregada  UNIQUEIDENTIFIER;
            DECLARE @idDefinitiva UNIQUEIDENTIFIER;
            SELECT @idEntregada  = MAX(CASE WHEN codigo = 'ENTREGADA' THEN id END),
                   @idDefinitiva = MAX(CASE WHEN codigo = 'FALLIDA_DEFINITIVA' THEN id END)
            FROM dbo.EstadoNotificacion;

            EXEC dbo.usp_depurar_notificaciones_salientes_interno
                @retencionDias = @retencionDias,
                @lote = @lote,
                @idEstadoEntregada = @idEntregada,
                @idEstadoDefinitiva = @idDefinitiva,
                @idCorrelacion = @idCorrelacionDefecto,
                @eliminadas = @eliminadas OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
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
        estadoResultado         = @estadoResultado,
        eliminadas              = @eliminadas;
END;
GO
