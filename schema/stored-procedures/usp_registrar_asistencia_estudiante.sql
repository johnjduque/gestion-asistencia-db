USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencia_estudiante]
(
    @idEstudianteGrupo UNIQUEIDENTIFIER,
    @idGrupoSesion UNIQUEIDENTIFIER,
    @idEstadoAsistencia UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @idEstudianteGrupoDefecto UNIQUEIDENTIFIER = ISNULL(@idEstudianteGrupo, '00000000-0000-0000-0000-000000000000');
    DECLARE @idGrupoSesionDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupoSesion, '00000000-0000-0000-0000-000000000000');
    DECLARE @idEstadoAsistenciaDefecto UNIQUEIDENTIFIER = ISNULL(@idEstadoAsistencia, '00000000-0000-0000-0000-000000000000');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar matricula (EstudianteGrupo)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_grupo_exista_interno
                @idEstudianteGrupo = @idEstudianteGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar sesion de clase
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idGrupoSesionDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Recuperar datos y sincronizar la asistencia
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idEstudiante UNIQUEIDENTIFIER;
            SELECT TOP 1 @idEstudiante = estudiante 
            FROM [dbo].[EstudianteGrupo]
            WHERE id = @idEstudianteGrupoDefecto;

            DECLARE @codigoEstado NVARCHAR(5);
            SELECT TOP 1 @codigoEstado = codigo 
            FROM [dbo].[RazonCausa]
            WHERE id = @idEstadoAsistenciaDefecto;

            IF @codigoEstado IS NULL
            BEGIN
                SET @codigoEstado = 'A';
            END

            -- Llamar al sincronizador interno
            EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                @idEstudiante = @idEstudiante,
                @idSesion = @idGrupoSesionDefecto,
                @codigoEstado = @codigoEstado,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Hubo un error inesperado al registrar la asistencia del estudiante.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_registrar_asistencia_estudiante]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH

    -- 5. Retornar resultado de la transaccion
    SELECT 
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END
GO
