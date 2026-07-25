USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_registro_estudiante_en_grupo]    Script Date: 24/07/2026 11:43:29 p. m. ******/
DROP PROCEDURE [dbo].[usp_validar_registro_estudiante_en_grupo]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_registro_estudiante_en_grupo]    Script Date: 24/07/2026 11:43:29 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_registro_estudiante_en_grupo_interno]
(
    @idGrupo UNIQUEIDENTIFIER,
    @idEstudiante UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idEstudiante,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));

    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar estudiante
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @idEstudianteDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar grupo
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar Duplicidad (Corregido: Usando @idEstudianteDefecto)
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @idGrupoDefecto AND idEstudiante = @idEstudianteDefecto)
            BEGIN
                SELECT @mensajeUsuarioResultado = 'Usted ya se encuentra registrado o matriculado en este grupo.',
                       @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Registro duplicado detectado. Estudiante: ', @idEstudianteDefecto, ' ya existe en Grupo: ', @idGrupoDefecto)),
                       @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Ocurrió un error al validar su registro previo.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_registro_estudiante_en_grupo_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END
GO


