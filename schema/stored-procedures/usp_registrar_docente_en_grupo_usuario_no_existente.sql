USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
(
    @idTipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion   INT,
    @primerApellido         NVARCHAR(255),
    @segundoApellido        NVARCHAR(255),
    @primerNombre           NVARCHAR(255),
    @segundoNombre          NVARCHAR(255),
    @correo                 NVARCHAR(255),
    @password               NVARCHAR(500),
    @idGrupo                UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idUsuarioCreado      UNIQUEIDENTIFIER;
    DECLARE @idDocenteCreado      UNIQUEIDENTIFIER;

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación de presencia del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Control y gestión del Usuario (Búsqueda por correo/documento -> Actualización si existe o Creación vía sincronización)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;

            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_reg_doc_grupo;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1
                @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = TRIM(@correo)
               OR (idTipoIdentificacion = @idTipoIdIdentificacion AND numeroIdentificacion = @numeroIdentificacion);

            IF @idUsuarioCreado IS NOT NULL
            BEGIN
                -- El usuario ya existe en el sistema: Validar estado activo y actualizar datos biográficos
                EXEC [dbo].[usp_validar_usuario_existe_por_id_interno]
                    @idUsuario = @idUsuarioCreado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    UPDATE u
                    SET u.tipoIdIdentificacion = @idTipoIdIdentificacion,
                        u.numeroIdentificacion = @numeroIdentificacion,
                        u.primerApellido = TRIM(@primerApellido),
                        u.segundoApellido = TRIM(@segundoApellido),
                        u.primerNombre = TRIM(@primerNombre),
                        u.segundoNombre = TRIM(@segundoNombre)
                    FROM [dbo].[Usuario] u
                    WHERE u.id = @idUsuarioCreado;
                END
            END
            ELSE
            BEGIN
                -- El usuario no existe: Crear y sincronizar registro de usuario en el sistema
                EXEC [dbo].[usp_sincronizar_usuario_interno]
                    @idTipoIdIdentificacion  = @idTipoIdIdentificacion,
                    @numeroIdentificacion    = @numeroIdentificacion,
                    @primerApellido          = @primerApellido,
                    @segundoApellido         = @segundoApellido,
                    @primerNombre            = @primerNombre,
                    @segundoNombre           = @segundoNombre,
                    @correo                  = @correo,
                    @password                = @password,
                    @idCorrelacion           = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado         = @estadoResultado OUTPUT;

                IF @estadoResultado = 1 
                BEGIN
                    SELECT TOP 1
                        @idUsuarioCreado = id
                    FROM [dbo].[uv_usuario]
                    WHERE correo = TRIM(@correo);
                END
            END
        END
       
        -- PASO 3: Control y gestión del perfil del Docente (Búsqueda en vista de identidad o Creación de perfil de docente)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idDocenteCreado = id
            FROM [dbo].[uv_docente_identidad]
            WHERE idUsuario = @idUsuarioCreado;

            IF @idDocenteCreado IS NULL
            BEGIN
                EXEC [dbo].[usp_sincronizar_docente_interno]
                    @idUsuario               = @idUsuarioCreado,
                    @idCorrelacion           = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado         = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1
                        @idDocenteCreado = id
                    FROM [dbo].[uv_docente_identidad]
                    WHERE idUsuario = @idUsuarioCreado;
                END
            END
        END
        
        -- PASO 4: Asignación y registro del Docente en el Grupo seleccionado
        IF @estadoResultado = 1
        BEGIN
            EXEC [dbo].[usp_registrar_docente_en_grupo_interno]
                @idDocente               = @idDocenteCreado,
                @idGrupo                 = @idGrupoDefecto,
                @idCorrelacion           = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado         = @estadoResultado OUTPUT;
        END
        
        -- PASO 5: Preparación del resultado de éxito antes de finalizar la transacción propia.
        -- Después del COMMIT no debe ejecutarse lógica que pueda convertir un éxito persistido en error.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo                = 'GEN_004',
                @p_param1                = 'DocenteGrupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 6: Finalización de la transacción respetando ownership (ver docs/procedimiento-transacciones)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION sp_reg_doc_grupo;
            -- XACT_STATE() = -1 con transacción externa: no es propietaria, no se toca (ver PASO 10 del contrato)
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones inesperadas y formateo mediante catálogo de mensajes y stack de error
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_reg_doc_grupo;
        END

        -- Transacción externa quedó doomed y no nos pertenece: propagar la excepción original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo                = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
