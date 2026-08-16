USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencia_estudiante_autonomo]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idSesion UNIQUEIDENTIFIER,
    @codigoVerificacion NVARCHAR(50),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = ISNULL(@idEstudiante, '00000000-0000-0000-0000-000000000000');
    DECLARE @idSesionDefecto UNIQUEIDENTIFIER = ISNULL(@idSesion, '00000000-0000-0000-0000-000000000000');
    DECLARE @codigoVerificacionDefecto NVARCHAR(50) = LTRIM(RTRIM(ISNULL(@codigoVerificacion, '')));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar pertenencia del estudiante al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto, @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar codigo de verificacion dinamico
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoReal NVARCHAR(50);
            SELECT TOP 1 @codigoReal = LTRIM(RTRIM(codigo))
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @codigoReal <> @codigoVerificacionDefecto
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El código de verificación ingresado es incorrecto o ha expirado.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: Código de verificación incorrecto. Esperado [', @codigoReal, '], Recibido [', @codigoVerificacionDefecto, ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
        END

        -- 5. Registrar asistencia auto-gestionada (como Asistió 'A')
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @codigoEstado = 'A',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Hubo un error inesperado al registrar tu asistencia.',
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto),
            @estadoResultado = 0;
    END CATCH

    -- 6. Retornar resultado de la transaccion
    SELECT 
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END
GO
