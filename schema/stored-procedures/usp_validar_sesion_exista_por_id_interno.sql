USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_exista_por_id_interno]
(
    @idSesion UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
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
        IF @estadoResultado = 1 AND @idSesionDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El identificador de sesión no es válido.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @idSesion es el GUID vacío. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Validacion de Existencia en la vista uv_sesion
        IF @estadoResultado = 1
        BEGIN
            DECLARE @existe BIT = 0;

            SELECT TOP 1 
                @existe = 1
            FROM [dbo].[uv_sesion]
            WHERE id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'La sesión de clase especificada no existe en el sistema.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: ID [', CAST(@idSesionDefecto AS NVARCHAR(50)), '] no encontrado en uv_sesion. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT 
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Sesión validada correctamente: ', @idSesionDefecto)),
                    @estadoResultado = 1;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar la información de la sesión.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_validar_sesion_exista_por_id_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
