USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantilla_notificacion_activa]
-- Capacidad: Plantillas de Notificacion (NOTIF-002A)
-- Ambito: Fachada publica tecnica para consultar la plantilla activa de un tipo
--         y sus marcadores declarados. Excepcion RBAC documentada (solo runtime,
--         igual que NOTIF-001 D9).
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): 0 o 1 fila (version, asunto, cuerpo)
--   Result set 3 (cuando estadoResultado=1): lista de marcadores (marcador, obligatorio)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantilla_notificacion_activa]
(
    @tipo          NVARCHAR(100)    = NULL,
    @idioma        CHAR(2)          = 'es',
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tipoDef              VARCHAR(60)      = NULL;
    DECLARE @idiomaDef            CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

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

        -- 2. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido (3-60 caracteres A-Z, 0-9, _). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 3. Preparar mensaje de exito GEN_003
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'PlantillaNotificacion',
                @p_param2 = @tipoDef,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
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

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: plantilla y marcadores cuando la validacion fue exitosa
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_plantilla_notificacion_activa_interno
            @tipo = @tipoDef,
            @idioma = @idiomaDef;
    END
END;
GO
