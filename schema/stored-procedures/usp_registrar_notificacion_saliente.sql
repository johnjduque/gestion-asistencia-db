USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_registrar_notificacion_saliente]
-- Capacidad: Notificaciones Outbox (NOTIF-001)
-- Ambito: Fachada publica tecnica de registro de notificaciones salientes.
-- Salida Canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso), PASO n, SET XACT_ABORT ON (fachada que muta), sin COALESCE (un IIF equivalente) y estado por uv_estado_notificacion (antes, la tabla). Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): notificaciones y correo: lo invoca el backend sin usuario con perfil; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_notificacion_saliente]
(
    @tipo               NVARCHAR(100)    = NULL,
    @asunto             NVARCHAR(400)    = NULL,
    @mensaje            NVARCHAR(MAX)    = NULL,
    @destinatariosJson  NVARCHAR(MAX)    = NULL,
    @datosJson          NVARCHAR(MAX)    = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER = NULL,
    @traceId            CHAR(32)         = NULL,
    @spanId             CHAR(16)         = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tipoDef              VARCHAR(60)      = NULL;
    DECLARE @asuntoDef            NVARCHAR(200)    = NULL;
    DECLARE @mensajeDef           NVARCHAR(4000)   = NULL;
    DECLARE @datosDef             NVARCHAR(MAX)    = IIF(NULLIF(TRIM(@datosJson), N'') IS NULL, N'{}', TRIM(@datosJson));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @tipoRaw NVARCHAR(100);
    DECLARE @asuntoRaw NVARCHAR(400);
    DECLARE @destTrim NVARCHAR(MAX);
    DECLARE @countDest INT;
    DECLARE @hayInvalido BIT;
    DECLARE @idEstadoPendiente UNIQUEIDENTIFIER;
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

        -- PASO 2: Validar tipo (3..60 caracteres, mayusculas A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            SET @tipoRaw = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo invalido (3-60 caracteres A-Z, 0-9, _). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- PASO 3: Validar asunto (opcional, <= 200 caracteres)
        IF @estadoResultado = 1 AND @asunto IS NOT NULL
        BEGIN
            SET @asuntoRaw = TRIM(@asunto);
            IF LEN(@asuntoRaw) > 200
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Asunto excede 200 caracteres. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @asuntoDef = CAST(@asuntoRaw AS NVARCHAR(200));
            END
        END

        -- PASO 4: Validar mensaje (opcional, <= 4000 caracteres)
        IF @estadoResultado = 1 AND @mensaje IS NOT NULL
        BEGIN
            IF LEN(@mensaje) > 4000
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Mensaje excede 4000 caracteres. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @mensajeDef = CAST(@mensaje AS NVARCHAR(4000));
            END
        END

        -- PASO 5: Validar destinatariosJson (requerido, JSON arreglo de 1..100 objetos con rol e idUsuario UUID)
        IF @estadoResultado = 1
        BEGIN
            SET @destTrim = TRIM(@destinatariosJson);
            IF @destTrim IS NULL OR @destTrim = N'' OR ISJSON(@destTrim) <> 1 OR LEFT(@destTrim, 1) <> '['
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Destinatarios no es un arreglo JSON valido. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @countDest = 0;
                SET @hayInvalido = 0;

                SELECT
                    @countDest = COUNT(*),
                    @hayInvalido = MAX(CASE
                        WHEN rol IS NULL OR TRIM(rol) = '' OR LEN(TRIM(rol)) > 30 THEN 1
                        WHEN idUsuario IS NULL OR TRY_CONVERT(UNIQUEIDENTIFIER, idUsuario) IS NULL THEN 1
                        ELSE 0
                    END)
                FROM OPENJSON(@destTrim)
                WITH (
                    rol       NVARCHAR(100) '$.rol',
                    idUsuario NVARCHAR(100) '$.idUsuario'
                );

                IF @countDest < 1 OR @countDest > 100 OR @hayInvalido = 1
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'NTF_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Destinatarios debe tener entre 1 y 100 elementos con rol valido y UUID idUsuario. Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- PASO 6: Validar datosJson (opcional, JSON objeto, <= 8000 caracteres)
        IF @estadoResultado = 1
        BEGIN
            IF ISJSON(@datosDef) <> 1 OR LEFT(TRIM(@datosDef), 1) <> '{' OR LEN(@datosDef) > 8000
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Datos no es un objeto JSON valido o excede 8000 caracteres. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Resolver estado PENDIENTE del catalogo
        SET @idEstadoPendiente = NULL;
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.uv_estado_notificacion WHERE codigo = 'PENDIENTE';
            IF @idEstadoPendiente IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SYS_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT('Estado PENDIENTE no configurado en EstadoNotificacion. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 8: Delegar al procedimiento interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_registrar_notificacion_saliente_interno
                @tipo = @tipoDef,
                @asunto = @asuntoDef,
                @mensaje = @mensajeDef,
                @destinatariosJson = @destinatariosJson,
                @datosJson = @datosDef,
                @idEstadoPendiente = @idEstadoPendiente,
                @traceId = @traceId,
                @spanId = @spanId,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        -- PASO 9: el interno ya revirtio lo suyo; la fachada no abre transaccion y responde SYS_001
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
