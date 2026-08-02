USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_validar_grupo_exista_por_id_interno]
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
        -- 1. Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar que el ID no sea el vacio (All zeros)
        IF @estadoResultado = 1 AND @idGrupoDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT @mensajeUsuarioResultado = 'El identificador del grupo no es valido.',
                   @mensajeTecnicoResultado = CONCAT('ID vacio. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                   @estadoResultado = 0;
        END

        -- 2. Validar que esta el id del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_id_interno 
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
                    @capacidadMaximaPermitida = capacidadMaximaPermitida, -- de la tabla Grupo voa uv_grupo
                    @cuposRestantes = cuposDisponibles -- Calculado en la vista
            FROM    dbo.uv_grupo 
            WHERE   id = @idGrupoDefecto;

            IF @@ROWCOUNT = 0
            BEGIN
                SELECT  @mensajeUsuarioResultado = CONCAT('No existe un grupo con el identificador [', @idGrupoDefecto, '] o no cumple con los requisitos de la vista.'),
                        @mensajeTecnicoResultado = CONCAT('No se encontro el registro en uv_grupo. Nota: La vista usa INNER JOINs, verifique integridad de datos. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                        @estadoResultado = 0;
            END
        END

        -- 4. Validar Semestre Acadomico
        IF @estadoResultado = 1 AND @idPeriodo IS NULL
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo no tiene un periodo academico valido asignado.',
                    @mensajeTecnicoResultado = CONCAT('El idPeriodoAcademicoGrupo es NULL en uv_grupo. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

        -- 5. Validar que el grupo esta habilitado
        IF @estadoResultado = 1 AND @grupoEstaHablitado = 0
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo seleccionado no se encuentra habilitado para el periodo academico actual.',
                    @mensajeTecnicoResultado = CONCAT('El atributo grupoEstaHablitado es 0 (Fecha actual fuera de rango pa.fechaInicio - pa.fechaFin). ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

        -- 6. Validar Tamaoo Moximo
        IF @estadoResultado = 1
        BEGIN
            IF @cuposRestantes <= 0
            BEGIN
                SELECT  @mensajeUsuarioResultado = 'El grupo ha superado el tamaoo moximo de estudiantes permitido.',
                        @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Cupo lleno. Activos: ', ISNULL(@estudiantesActivos, 0), ' / Capacidad Moxima: ', ISNULL(@capacidadMaximaPermitida, 0))),
                        @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Error al validar que el grupo existe.',
               @mensajeTecnicoResultado = CONCAT('Error critico en orquestador [usp_validar_grupo_exista_por_id_interno]: ', ERROR_MESSAGE(), '. Linea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END
GO
