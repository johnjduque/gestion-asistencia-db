USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]    Script Date: 22/07/2026 11:55:06 p. m. ******/
DROP PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
GO

/****** Object:  StoredProcedure [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]    Script Date: 22/07/2026 11:55:06 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE  OR  ALTER    PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
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
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @grupoDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000');
    
    DECLARE @idUsuarioCreado UNIQUEIDENTIFIER;
    DECLARE @idEstudianteCreado UNIQUEIDENTIFIER;
    DECLARE @idProgramaGrupo UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioCreado = id 
            FROM [dbo].[uv_usuario] 
            WHERE correo = LOWER(LTRIM(RTRIM(@correo))) 
               OR (idTipoIdentificacion = @tipoIdIdentificacion AND numeroIdentificacion = @numeroIdentificacion);
        END

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
                    SELECT TOP 1 @idUsuarioCreado = id FROM [dbo].[uv_usuario] WHERE correo = LOWER(LTRIM(RTRIM(@correo)));
                END
            END
        END
       
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteCreado = id 
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
                    SELECT TOP 1 @idEstudianteCreado = id FROM [dbo].[uv_estudiante_identidad] WHERE idUsuario = @idUsuarioCreado;
                END
            END
            ELSE
            BEGIN
                SET @mensajeTecnicoResultado = 'Perfil base de estudiante verificado.';
            END
        END
        
        -- PASO 3 
        IF @estadoResultado = 1
        BEGIN
            EXEC [dbo].[usp_registrar_estudiante_en_grupo_interno]
                @estudiante = @idEstudianteCreado,
                @grupo = @grupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idProgramaGrupo = pe.idPrograma
            FROM [dbo].[uv_grupo] g
            INNER JOIN [dbo].[uv_asignatura] a ON g.idAsignatura = a.id
            INNER JOIN [dbo].[uv_semestre_plan_estudio] spe ON a.idSemestrePlanEstudio = spe.id
            INNER JOIN [dbo].[uv_plan_estudio] pe ON spe.idPlanEstudio = pe.id
            WHERE g.id = @grupoDefecto;

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
                    @mensajeUsuarioResultado = 'No se encontró un programa académico asociado a este grupo.',
                    @mensajeTecnicoResultado = CONCAT('Error: Trazabilidad rota para Grupo ID ', @grupoDefecto),
                    @estadoResultado = 0;
            END
        END
        
        IF @estadoResultado = 1
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'Se ha enrolado el estudiante en el grupo de forma sactisfactoria',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Orquestador finalizado para Estudiante: ', @idEstudianteCreado, ' en Grupo: ', @grupoDefecto))
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Hubo un error inesperado al procesar el registro completo del estudiante.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH           

    SELECT 
        id = @idCorrelacionDefecto, 
        mensajeUsuarioResultado = @mensajeUsuarioResultado, 
        mensajeTecnicoResultado = @mensajeTecnicoResultado, 
        estadoResultado = @estadoResultado;    
END
GO


