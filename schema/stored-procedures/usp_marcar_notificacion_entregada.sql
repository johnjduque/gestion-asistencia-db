USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_marcar_notificacion_entregada]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Fachada publica tecnica para confirmar entrega exitosa.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso), PASO n, SET XACT_ABORT ON (fachada que muta) y lecturas por uv_estado_notificacion/uv_notificacion_saliente (antes, las tablas). Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): notificaciones y correo: lo invoca el backend sin usuario con perfil; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_marcar_notificacion_entregada]
(
    @id            UNIQUEIDENTIFIER = NULL,
    @instancia     NVARCHAR(100)    = NULL,
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @ahora DATETIMEOFFSET(7);
    DECLARE @idReservada UNIQUEIDENTIFIER;
    DECLARE @idEntregada UNIQUEIDENTIFIER;
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

        -- PASO 2: Validar existencia del id
        IF @estadoResultado = 1 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_notificacion_saliente WHERE id = @id))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Id inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar reserva vigente de la instancia
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

        -- PASO 4: Delegar al interno
        IF @estadoResultado = 1
        BEGIN
            SET @idEntregada = (SELECT TOP 1 id FROM dbo.uv_estado_notificacion WHERE codigo = 'ENTREGADA');
            EXEC dbo.usp_marcar_notificacion_entregada_interno
                @id = @id,
                @idEstadoEntregada = @idEntregada,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: el interno ya revirtio lo suyo; la fachada no abre transaccion y responde SYS_001
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
