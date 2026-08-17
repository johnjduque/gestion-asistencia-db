USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
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
DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

DECLARE @idUsuarioCreado    UNIQUEIDENTIFIER;
DECLARE @idEstudianteCreado UNIQUEIDENTIFIER;
DECLARE @idProgramaGrupo    UNIQUEIDENTIFIER;

DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado BIT = 1;

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
       
        -- PASO 3: Control y gestión del perfil del Estudiante (Búsqueda en vista de identidad o Creación de perfil de estudiante)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idEstudianteCreado = id
            FROM [dbo].[uv_estudiante_identidad]
            WHERE idUsuario = @idUsuarioCreado;

            IF @idEstudianteCreado IS NULL
            BEGIN
                EXEC [dbo].[usp_sincronizar_estudiante_interno]
                    @idUsuario               = @idUsuarioCreado,
                    @idCorrelacion           = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado         = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1
                        @idEstudianteCreado = id
                    FROM [dbo].[uv_estudiante_identidad]
                    WHERE idUsuario = @idUsuarioCreado;
                END
            END
        END
        
        -- PASO 4: Inscripción y registro del Estudiante en el Grupo seleccionado
        IF @estadoResultado = 1
        BEGIN
            EXEC [dbo].[usp_registrar_estudiante_en_grupo_interno]
                @idEstudiante            = @idEstudianteCreado,
                @idGrupo                 = @idGrupoDefecto,
                @idCorrelacion           = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado         = @estadoResultado OUTPUT;
        END
        
        -- PASO 5: Vinculación del Estudiante al Programa Académico del Grupo y validación de trazabilidad institucional
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
                -- Inconsistencia de trazabilidad: Grupo sin programa académico asociado. Obtención de mensajes desde catálogo
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_PROGRAMA_GRUPO_NO_ENCONTRADO',
                    @p_param1 = @idGrupoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        
        -- PASO 6: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SUC_REGISTRO_ESTUDIANTE_GRUPO',
                @p_param1 = @idEstudianteCreado,
                @p_param2 = @idGrupoDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones inesperadas y formateo mediante catálogo de mensajes y stack de error
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ERR_INESPERADO_REGISTRO_ESTUDIANTE',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO