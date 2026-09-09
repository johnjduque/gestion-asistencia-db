USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano]
(
    @idDecano               UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER,
    @nombreFacultad          NVARCHAR(150),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDecano, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreFacultadDef    NVARCHAR(150)    = TRIM(@nombreFacultad);

    DECLARE @idUsuarioCreado Uniqueidentifier;
    DECLARE @idTipoIdCC      UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Resolver facultad destino si se suministra el nombre
        IF @estadoResultado = 1 AND @idFacultadDefecto IS NULL AND @nombreFacultadDef IS NOT NULL AND @nombreFacultadDef <> ''
        BEGIN
            SELECT TOP 1 @idFacultadDefecto = id
            FROM [dbo].[uv_facultad]
            WHERE LOWER(nombreFacultad) = LOWER(@nombreFacultadDef)
               OR LOWER(nombreFacultad) LIKE LOWER(CONCAT('%', @nombreFacultadDef, '%'))
            ORDER BY nombreFacultad ASC;
        END

        -- PASO 3: GESTIÓN REACTIVA DE USUARIO (Consulta en uv_usuario y delegación a usp_sincronizar_usuario_interno)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioCreado IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC' ORDER BY id ASC;
                IF @idTipoIdCC IS NULL SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion ORDER BY id ASC;

                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdCC,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioCreado = id
                    FROM [dbo].[uv_usuario]
                    WHERE correo = LOWER(TRIM(@correo));
                END
            END
        END

        -- PASO 4: Asignación reactiva de rol Decano y adscripción a la Facultad
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            IF NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE usuario = @idUsuarioCreado)
            BEGIN
                INSERT INTO dbo.Decano (id, usuario)
                VALUES (@idDecanoDefecto, @idUsuarioCreado);
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDecanoDefecto = id FROM dbo.Decano WHERE usuario = @idUsuarioCreado;
            END

            IF @idFacultadDefecto IS NOT NULL
            BEGIN
                UPDATE dbo.Facultad
                SET decano = @idDecanoDefecto
                WHERE id = @idFacultadDefecto;
            END

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
