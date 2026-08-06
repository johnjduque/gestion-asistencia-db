USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_estudiante_grupo_exista_interno]
(
    @idEstudianteGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idEstudianteGrupoDefecto UNIQUEIDENTIFIER = ISNULL(@idEstudianteGrupo, '00000000-0000-0000-0000-000000000000');

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
        IF @estadoResultado = 1 AND @idEstudianteGrupoDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El registro de matrícula estudiantil no es válido.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @idEstudianteGrupo es el GUID vacío. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Validacion de Existencia y Estado en la vista uv_estudiante_grupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @existe BIT = 0;
            DECLARE @estadoActivo BIT = 0;

            SELECT TOP 1 
                @existe = 1,
                @estadoActivo = CASE WHEN codigoEstadoEstudiante = 'A' THEN 1 ELSE 0 END
            FROM [dbo].[uv_estudiante_grupo]
            WHERE id = @idEstudianteGrupoDefecto;

            IF @existe = 0
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El estudiante no se encuentra matriculado en el grupo.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: ID de relación EstudianteGrupo [', CAST(@idEstudianteGrupoDefecto AS NVARCHAR(50)), '] no encontrado. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE IF @estadoActivo = 0
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'La matrícula del estudiante en el grupo no está activa.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: EstudianteGrupo [', CAST(@idEstudianteGrupoDefecto AS NVARCHAR(50)), '] no tiene estado activo [A]. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT 
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Matrícula de estudiante validada correctamente: ', @idEstudianteGrupoDefecto)),
                    @estadoResultado = 1;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar el registro de matrícula del estudiante.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_validar_estudiante_grupo_exista_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
