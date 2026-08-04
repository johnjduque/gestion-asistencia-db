USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idSesion UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = ISNULL(@idEstudiante, '00000000-0000-0000-0000-000000000000');
    DECLARE @idSesionDefecto UNIQUEIDENTIFIER = ISNULL(@idSesion, '00000000-0000-0000-0000-000000000000');

    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

    SET NOCOUNT ON;
    BEGIN TRY

        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validacion de GUID vacio
        IF @estadoResultado = 1 AND (@idEstudianteDefecto = '00000000-0000-0000-0000-000000000000' OR @idSesionDefecto = '00000000-0000-0000-0000-000000000000')
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'Los datos del estudiante o de la sesión no son válidos.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @idEstudiante o @idSesion es el GUID vacío. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Validar relacion en uv_sesion y uv_estudiante_grupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idGrupo UNIQUEIDENTIFIER;

            -- 3.1 Obtener el grupo de la sesión
            SELECT TOP 1 
                @idGrupo = idGrupo
            FROM [dbo].[uv_sesion]
            WHERE id = @idSesionDefecto;

            IF @idGrupo IS NULL
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'La sesión especificada no está asociada a ningún grupo válido.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: No se encontró grupo para la sesión [', CAST(@idSesionDefecto AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
                RETURN;
            END

            -- 3.2 Validar que el estudiante pertenezca de forma activa a este grupo
            DECLARE @pertenece BIT = 0;

            SELECT TOP 1 
                @pertenece = 1
            FROM [dbo].[uv_estudiante_grupo]
            WHERE idEstudiante = @idEstudianteDefecto 
              AND idGrupo = @idGrupo 
              AND codigoEstadoEstudiante = 'A';

            IF @pertenece = 0
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El estudiante no está matriculado de forma activa en el grupo correspondiente a esta sesión.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: Estudiante [', CAST(@idEstudianteDefecto AS NVARCHAR(50)), '] no está inscrito activamente en el Grupo [', CAST(@idGrupo AS NVARCHAR(50)), '] para la Sesión [', CAST(@idSesionDefecto AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT 
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Estudiante pertenece al grupo de la sesión de forma activa. Estudiante: ', @idEstudianteDefecto, ' Sesión: ', @idSesionDefecto)),
                    @estadoResultado = 1;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar la pertenencia del estudiante al grupo de la sesión.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
