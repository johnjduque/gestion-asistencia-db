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
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso), PASO n, SET XACT_ABORT ON (fachada que muta) y lecturas por uv_estado_notificacion/uv_notificacion_saliente (antes, las tablas); sin ISNULL (un IIF equivalente). Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): notificaciones y correo: lo invoca el backend sin usuario con perfil; exige @idCorrelacion.
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
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @ahora DATETIMEOFFSET(7);
    DECLARE @idReservada UNIQUEIDENTIFIER;
    DECLARE @idReintentable UNIQUEIDENTIFIER;
    DECLARE @idDefinitiva UNIQUEIDENTIFIER;
    DECLARE @detalleTruncado NVARCHAR(300);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar parametros tecnicos obligatorios
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

        -- PASO 3: Validar existencia del id
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_notificacion_saliente WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Id inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Validar reserva vigente de la instancia
        IF @estadoResultado = 1
        BEGIN
            SET @ahora = SYSUTCDATETIME();
            SET @idReservada = (SELECT TOP 1 id FROM dbo.uv_estado_notificacion WHERE codigo = 'RESERVADA');

            IF NOT EXISTS (
                SELECT 1 FROM dbo.uv_notificacion_saliente
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

        -- PASO 5: Delegar al interno
        IF @estadoResultado = 1
        BEGIN
            SELECT @idReintentable = MAX(CASE WHEN codigo = 'FALLIDA_REINTENTABLE' THEN id END),
                   @idDefinitiva   = MAX(CASE WHEN codigo = 'FALLIDA_DEFINITIVA' THEN id END)
            FROM dbo.uv_estado_notificacion;

            SET @detalleTruncado = SUBSTRING(IIF(@detalleError IS NULL, N'', @detalleError), 1, 300);

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
        -- PASO 6: el interno ya revirtio lo suyo; la fachada no abre transaccion y responde SYS_001
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
