USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
(
    @tipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @primerApellido NVARCHAR(255),
    @segundoApellido NVARCHAR(255),
    @primerNombre NVARCHAR(255),
    @segundoNombre NVARCHAR(255),
    @correo NVARCHAR(255),
    @password NVARCHAR(255),
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    -- PASO 0: Limpieza, sanitización de variables y recuperación de parámetros por defecto
    SET @correo = TRIM(@correo);
    SET @primerNombre = TRIM(@primerNombre);
    SET @segundoNombre = TRIM(@segundoNombre);
    SET @primerApellido = TRIM(@primerApellido);
    SET @segundoApellido = TRIM(@segundoApellido);

    DECLARE @cadenaVaciaDefecto NVARCHAR(4000) = ISNULL(dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'), '');

    DECLARE @uuidDefecto UNIQUEIDENTIFIER = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'UUID_DEFECTO') AS UNIQUEIDENTIFIER);
    IF @uuidDefecto IS NULL
        SET @uuidDefecto = '00000000-0000-0000-0000-000000000000';

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, @uuidDefecto);
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupo, @uuidDefecto);

    DECLARE @idUsuarioCreado UNIQUEIDENTIFIER;
    DECLARE @idEstudianteCreado UNIQUEIDENTIFIER;
    DECLARE @idProgramaGrupo UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = @cadenaVaciaDefecto;
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = @cadenaVaciaDefecto;
    DECLARE @estadoResultado BIT = 1;

    BEGIN TRY
        -- Validar presencia de ID de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1: Control de Usuario (Consultar -> Actualizar / Crear)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = @correo
               OR (idTipoIdentificacion = @tipoIdIdentificacion AND numeroIdentificacion = @numeroIdentificacion);

            IF @idUsuarioCreado IS NOT NULL
            BEGIN
                -- Si el usuario ya existe: Validar y Actualizar
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
                        u.primerApellido = @primerApellido,
                        u.segundoApellido = @segundoApellido,
                        u.primerNombre = @primerNombre,
                        u.segundoNombre = @segundoNombre
                    FROM [dbo].[Usuario] u
                    WHERE u.id = @idUsuarioCreado;
                END
            END
            ELSE
            BEGIN
                -- Si no existe: Crear/Sincronizar usuario
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
                    WHERE correo = @correo;
                END
            END
        END

        -- PASO 2: Control de Perfil de Estudiante (Consultar -> Crear)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idEstudianteCreado = id
            FROM [dbo].[uv_estudiante_identidad]
            WHERE idUsuario = @idUsuarioCreado;

            IF @idEstudianteCreado IS NULL
            BEGIN
                EXEC [dbo].[usp_sincronizar_estudiante_interno]
                    @idUsuario = @idUsuarioCreado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1
                        @idEstudianteCreado = id
                    FROM [dbo].[uv_estudiante_identidad]
                    WHERE idUsuario = @idUsuarioCreado;
                END
            END
        END

        -- PASO 3: Registrar Estudiante en el Grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC [dbo].[usp_registrar_estudiante_en_grupo_interno]
                @estudiante = @idEstudianteCreado,
                @grupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Asignar Estudiante al Programa Académico del Grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idProgramaGrupo = pe.idPrograma
            FROM [dbo].[uv_grupo] g
                INNER JOIN [dbo].[uv_asignatura] a ON g.idAsignatura = a.id
                INNER JOIN [dbo].[uv_semestre_plan_estudio] spe ON a.idSemestrePlanEstudio = spe.id
                INNER JOIN [dbo].[uv_plan_estudio] pe ON spe.idPlanEstudio = pe.id
            WHERE g.id = @idGrupoDefecto;

            IF @idProgramaGrupo IS NOT NULL
            BEGIN
                EXEC [dbo].[usp_registrar_estudiante_en_programa_interno]
                    @idEstudiante = @idEstudianteCreado,
                    @idPrograma = @idProgramaGrupo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                    @estadoResultado = @estadoResultado OUTPUT;
            END
            ELSE
            BEGIN
                SELECT
                    @mensajeUsuarioResultado = ISNULL(dbo.ufn_obtener_mensaje('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'USUARIO', 'Programa'), 'No se encontró un programa académico asociado a este grupo.'),
                    @mensajeTecnicoResultado = ISNULL(dbo.ufn_obtener_mensaje('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'TECNICO', CONCAT('Grupo ID ', @idGrupoDefecto)), CONCAT('Error: Trazabilidad rota para Grupo ID ', @idGrupoDefecto)),
                    @estadoResultado = 0;
            END
        END

        -- PASO 5: Evaluación de Resultado Final
        IF @estadoResultado = 1
        BEGIN
            SELECT
                @mensajeUsuarioResultado = ISNULL(dbo.ufn_obtener_mensaje('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'USUARIO', 'Estudiante'), 'Se ha registrado el estudiante en el grupo de forma satisfactoria'),
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Orquestador finalizado para Estudiante: ', @idEstudianteCreado, ' en Grupo: ', @idGrupoDefecto));
        END

    END TRY
    BEGIN CATCH
        SELECT
            @mensajeUsuarioResultado = ISNULL(dbo.ufn_obtener_mensaje('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'USUARIO', 'Estudiante'), 'Hubo un error inesperado al procesar el registro completo del estudiante.'),
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto),
            @estadoResultado = 0;
    END CATCH

    -- Retorno unificado de resultados
    SELECT
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO