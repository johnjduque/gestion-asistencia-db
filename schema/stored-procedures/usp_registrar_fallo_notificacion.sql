USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_registrar_fallo_notificacion]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Fachada publica tecnica para registrar fallos y calcular reintentos.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_fallo_notificacion]
(
    @id                  UNIQUEIDENTIFIER = NULL,
    @instancia           NVARCHAR(100)    = NULL,
    @codigoError         VARCHAR(40)      = NULL,
    @detalleError        NVARCHAR(300)    = NULL,
    @reintentable        BIT              = NULL,
    @maxIntentos         INT              = 5,
    @backoffBaseSegundos INT              = 30,
    @backoffMaxSegundos  INT              = 900,
    @idCorrelacion       UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
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

        -- 2. Validar parametros tecnicos obligatorios
        IF @estadoResultado = 1
        BEGIN
            IF @reintentable IS NULL
               OR @codigoError IS NULL OR TRIM(@codigoError) = '' OR LEN(@codigoError) > 40
               OR @maxIntentos IS NULL OR @maxIntentos < 1 OR @maxIntentos > 20
               OR @backoffBaseSegundos IS NULL OR @backoffBaseSegundos < 1 OR @backoffBaseSegundos > 3600
               OR @backoffMaxSegundos IS NULL OR @backoffMaxSegundos < @backoffBaseSegundos OR @backoffMaxSegundos > 86400
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Parametros de fallo o backoff invalidos. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- 3. Validar existencia del id
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Id inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 4. Validar reserva vigente de la instancia
        IF @estadoResultado = 1
        BEGIN
            DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();
            DECLARE @idReservada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');

            IF NOT EXISTS (
                SELECT 1 FROM dbo.NotificacionSaliente
                WHERE id = @id
                  AND idEstado = @idReservada
                  AND reservadoPor = @instancia
                  AND reservadoHasta >= @ahora
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_003',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Notificacion no reservada o reserva vencida para la instancia. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- 5. Delegar al interno
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idReintentable UNIQUEIDENTIFIER;
            DECLARE @idDefinitiva   UNIQUEIDENTIFIER;
            SELECT @idReintentable = MAX(CASE WHEN codigo = 'FALLIDA_REINTENTABLE' THEN id END),
                   @idDefinitiva   = MAX(CASE WHEN codigo = 'FALLIDA_DEFINITIVA' THEN id END)
            FROM dbo.EstadoNotificacion;

            DECLARE @detalleTruncado NVARCHAR(300) = SUBSTRING(ISNULL(@detalleError, N''), 1, 300);

            EXEC dbo.usp_registrar_fallo_notificacion_interno
                @id = @id,
                @codigoError = @codigoError,
                @detalleError = @detalleTruncado,
                @reintentable = @reintentable,
                @maxIntentos = @maxIntentos,
                @backoffBaseSegundos = @backoffBaseSegundos,
                @backoffMaxSegundos = @backoffMaxSegundos,
                @idEstadoReintentable = @idReintentable,
                @idEstadoDefinitiva = @idDefinitiva,
                @idCorrelacion = @idCorrelacionDefecto,
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
        estadoResultado         = @estadoResultado;
END;
GO
