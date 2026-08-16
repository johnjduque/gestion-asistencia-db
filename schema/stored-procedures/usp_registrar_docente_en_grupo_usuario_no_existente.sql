USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
(
    @tipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @primerApellido NVARCHAR(255),
    @segundoApellido NVARCHAR(255),
    @primerNombre NVARCHAR(255),
    @segundoNombre NVARCHAR(255),
    @correo NVARCHAR(255),
    @password NVARCHAR(MAX),
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @grupoDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000');

    DECLARE @idUsuarioCreado UNIQUEIDENTIFIER;
    DECLARE @idDocenteCreado UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

    SET NOCOUNT ON;
    BEGIN TRY

        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Buscar si el usuario ya existe en el sistema
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(LTRIM(RTRIM(@correo)))
               OR (idTipoIdentificacion = @tipoIdIdentificacion AND numeroIdentificacion = @numeroIdentificacion);
        END

        -- 3. Si el usuario existe, validarlo y actualizarlo. Si no, crearlo.
        IF @estadoResultado = 1
        BEGIN
            IF @idUsuarioCreado IS NOT NULL
            BEGIN
                EXEC [dbo].[usp_validar_usuario_existe_por_id_interno]
                    @idUsuario = @idUsuarioCreado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    UPDATE u
                    SET u.tipoIdIdentificacion = @tipoIdIdentificacion,
                        u.numeroIdentificacion = @numeroIdentificacion,
                        u.primerApellido = UPPER(LTRIM(RTRIM(@primerApellido))),
                        u.segundoApellido = UPPER(LTRIM(RTRIM(@segundoApellido))),
                        u.primerNombre = UPPER(LTRIM(RTRIM(@primerNombre))),
                        u.segundoNombre = UPPER(LTRIM(RTRIM(@segundoNombre)))
                    FROM [dbo].[Usuario] u
                    WHERE u.id = @idUsuarioCreado;

                    SET @mensajeTecnicoResultado = 'Usuario preexistente validado. Datos actualizados.';
                END
            END
            ELSE
            BEGIN
                EXEC [dbo].[usp_sincronizar_usuario_interno]
                    @tipoIdIdentificacion = @tipoIdIdentificacion,
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
                    SELECT TOP 1
                        @idUsuarioCreado = id
                    FROM [dbo].[uv_usuario]
                    WHERE correo = LOWER(LTRIM(RTRIM(@correo)));
                END
            END
        END
       
        -- 4. Verificar perfil de Docente
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idDocenteCreado = id
            FROM [dbo].[uv_docente_identidad]
            WHERE idUsuario = @idUsuarioCreado;

            IF @idDocenteCreado IS NULL
            BEGIN
                EXEC [dbo].[usp_sincronizar_docente_interno]
                    @idUsuario = @idUsuarioCreado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1
                        @idDocenteCreado = id
                    FROM [dbo].[uv_docente_identidad]
                    WHERE idUsuario = @idUsuarioCreado;
                END
            END
            ELSE
            BEGIN
                SET @mensajeTecnicoResultado = 'Perfil base de docente verificado.';
            END
        END
        
        -- 5. Asignar el docente al grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC [dbo].[usp_registrar_docente_en_grupo_interno]
                @docente = @idDocenteCreado,
                @grupo = @grupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        
        -- 6. Respuesta final exitosa
        IF @estadoResultado = 1
        BEGIN
            SELECT
                @mensajeUsuarioResultado = 'Se ha registrado el docente en el grupo de forma satisfactoria',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operacion exitosa completa. Orquestador finalizado para Docente: ', @idDocenteCreado, ' en Grupo: ', @grupoDefecto))
        END

    END TRY
    BEGIN CATCH
        SELECT
            @mensajeUsuarioResultado = 'Hubo un error inesperado al procesar el registro completo del docente.',
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto),
            @estadoResultado = 0;
    END CATCH

    SELECT
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
