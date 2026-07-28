USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_grupo_exista_por_id]    Script Date: 24/07/2026 8:31:31 p. m. ******/
DROP PROCEDURE IF EXISTS [dbo].[usp_validar_grupo_exista_por_id]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_grupo_exista_por_id]    Script Date: 24/07/2026 8:31:31 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_grupo_exista_por_id_interno]
(
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER;

    SET @idGrupoDefecto = UPPER(LTRIM(RTRIM(ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000'))));
    SET @idCorrelacionDefecto = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));

    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

BEGIN
    --------------------------------------------------------------------
    -- Bloque principal
    --------------------------------------------------------------------
    BEGIN TRY
        -- 1. Validar correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar que el ID no sea el vacío (All zeros)
        IF @estadoResultado = 1 AND @idGrupoDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT @mensajeUsuarioResultado = 'El identificador del grupo no es válido.',
                   @mensajeTecnicoResultado = CONCAT('ID vacío. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                   @estadoResultado = 0;
        END

        -- 2. Validar que esté el id del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC usp_validar_id 
                @id = @idGrupoDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar Existencia y Obtener Atributos de la Vista uv_grupo
        DECLARE @idPeriodo UNIQUEIDENTIFIER;
        DECLARE @grupoEstaHablitado BIT;
        DECLARE @estudiantesActivos INT;
        DECLARE @capacidadMaximaPermitida INT;
        DECLARE @cuposRestantes INT;

        IF @estadoResultado = 1
        BEGIN
            SELECT  @idPeriodo = idPeriodoAcademico,
                    @grupoEstaHablitado = grupoEstaHablitado,
                    @estudiantesActivos = estudiantesActivos,
                    @capacidadMaximaPermitida = capacidadMaximaPermitida, -- de la tabla Grupo vía uv_grupo
                    @cuposRestantes = cuposDisponibles -- Calculado en la vista
            FROM    dbo.uv_grupo 
            WHERE   id = @idGrupoDefecto;

            IF @@ROWCOUNT = 0
            BEGIN
                SELECT  @mensajeUsuarioResultado = CONCAT('No existe un grupo con el identificador [', @idGrupoDefecto, '] o no cumple con los requisitos de la vista.'),
                        @mensajeTecnicoResultado = CONCAT('No se encontró el registro en uv_grupo. Nota: La vista usa INNER JOINs, verifique integridad de datos. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                        @estadoResultado = 0;
            END
        END

        -- 4. Validar Semestre Académico
        IF @estadoResultado = 1 AND @idPeriodo IS NULL
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo no tiene un periodo académico válido asignado.',
                    @mensajeTecnicoResultado = CONCAT('El idPeriodoAcademicoGrupo es NULL en uv_grupo. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

        -- 5. Validar que el grupo esté habilitado
        IF @estadoResultado = 1 AND @grupoEstaHablitado = 0
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo seleccionado no se encuentra habilitado para el periodo académico actual.',
                    @mensajeTecnicoResultado = CONCAT('El atributo grupoEstaHablitado es 0 (Fecha actual fuera de rango pa.fechaInicio - pa.fechaFin). ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

        -- 6. Validar Tamaño Máximo
        IF @estadoResultado = 1
        BEGIN
            IF @cuposRestantes <= 0
            BEGIN
                SELECT  @mensajeUsuarioResultado = 'El grupo ha superado el tamaño máximo de estudiantes permitido.',
                        @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Cupo lleno. Activos: ', ISNULL(@estudiantesActivos, 0), ' / Capacidad Máxima: ', ISNULL(@capacidadMaximaPermitida, 0))),
                        @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Error al validar que el grupo existe.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_grupo_exista_por_id_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END
GO


