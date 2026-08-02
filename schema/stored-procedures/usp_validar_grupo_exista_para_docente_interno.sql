USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_grupo_exista_para_docente_interno]
(
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));

    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar que el ID no sea el vacío
        IF @estadoResultado = 1 AND @idGrupoDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT @mensajeUsuarioResultado = 'El identificador del grupo no es válido.',
                   @mensajeTecnicoResultado = CONCAT('ID vacío. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                   @estadoResultado = 0;
        END

        -- 3. Validar ID en tabla
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_id_interno 
                @id = @idGrupoDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar Existencia en la Vista uv_grupo
        DECLARE @idPeriodo UNIQUEIDENTIFIER;
        DECLARE @grupoEstaHabilitado BIT;

        IF @estadoResultado = 1
        BEGIN
            SELECT  @idPeriodo = idPeriodoAcademico,
                    @grupoEstaHabilitado = grupoEstaHablitado
            FROM    dbo.uv_grupo 
            WHERE   id = @idGrupoDefecto;

            IF @@ROWCOUNT = 0
            BEGIN
                SELECT  @mensajeUsuarioResultado = CONCAT('No existe un grupo con el identificador [', @idGrupoDefecto, '].'),
                        @mensajeTecnicoResultado = CONCAT('No se encontró el registro en uv_grupo. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                        @estadoResultado = 0;
            END
        END

        -- 5. Validar Periodo Académico
        IF @estadoResultado = 1 AND @idPeriodo IS NULL
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo no tiene un periodo académico válido asignado.',
                    @mensajeTecnicoResultado = CONCAT('El idPeriodoAcademicoGrupo es NULL en uv_grupo. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

        -- 6. Validar que el grupo esté habilitado (fecha actual en el rango del periodo)
        IF @estadoResultado = 1 AND @grupoEstaHabilitado = 0
        BEGIN
            SELECT  @mensajeUsuarioResultado = 'El grupo seleccionado no se encuentra habilitado para el periodo académico actual.',
                    @mensajeTecnicoResultado = CONCAT('El atributo grupoEstaHabilitado es 0. ID CORRELACION=[', @idCorrelacionDefecto, ']'),
                    @estadoResultado = 0;
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Error al validar la existencia del grupo para el docente.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_grupo_exista_para_docente_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END;
GO
