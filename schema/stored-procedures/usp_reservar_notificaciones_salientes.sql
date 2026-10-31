USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reservar_notificaciones_salientes]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Fachada publica tecnica de reserva concurrente de notificaciones.
-- Salida: Filas reservadas (id, tipo, asunto, mensaje, destinatarios, datos,
--         intentos, creadoEn, idCorrelacion, traceId, spanId)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_reservar_notificaciones_salientes]
(
    @lote          INT              = 50,
    @leaseSegundos INT              = 60,
    @instancia     NVARCHAR(100)    = NULL,
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- 1. Validar idCorrelacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- 2. Validar lote (1..500)
    IF @lote IS NULL OR @lote < 1 OR @lote > 500
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Lote fuera de rango (1-500). Correlacion: ', @idCorrelacionDefecto);
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- 3. Validar leaseSegundos (5..3600)
    IF @leaseSegundos IS NULL OR @leaseSegundos < 5 OR @leaseSegundos > 3600
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Lease fuera de rango (5-3600 segundos). Correlacion: ', @idCorrelacionDefecto);
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- 4. Validar instancia
    IF @instancia IS NULL OR TRIM(@instancia) = N''
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Instancia requerida. Correlacion: ', @idCorrelacionDefecto);
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- 5. Invocar interno
    EXEC dbo.usp_reservar_notificaciones_salientes_interno
        @lote = @lote,
        @leaseSegundos = @leaseSegundos,
        @instancia = @instancia,
        @idCorrelacion = @idCorrelacionDefecto;
END;
GO
