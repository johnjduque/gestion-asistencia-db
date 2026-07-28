USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_perfil_existe_por_codigo]    Script Date: 24/07/2026 11:28:39 p. m. ******/
DROP PROCEDURE IF EXISTS [dbo].[usp_validar_perfil_existe_por_codigo]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_perfil_existe_por_codigo]    Script Date: 24/07/2026 11:28:39 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_perfil_existe_por_codigo_interno]
(
    @codigoPerfil NVARCHAR(10),
    @idCorrelacion UNIQUEIDENTIFIER,
    @idPerfilEncontrado UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS


    -- 1. Estandarización de variables locales
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @codigoPerfilDefecto NVARCHAR(10) = UPPER(LTRIM(RTRIM(ISNULL(@codigoPerfil, ''))));

    -- Inicialización de variables de salida
    SELECT 
        @idPerfilEncontrado = '00000000-0000-0000-0000-000000000000',
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
     
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
       
        -- 2. Validación de entrada (Código vacío)
        IF @codigoPerfilDefecto = ''
        BEGIN
        
            SELECT 
                @mensajeUsuarioResultado = 'El código de perfil no puede estar vacío.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @codigoPerfil es nulo o vacío. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Búsqueda y Validación de existencia en la VISTA uv_perfil
        SELECT TOP 1 
            @idPerfilEncontrado = id 
        FROM [dbo].[uv_perfil] 
        WHERE codigo = @codigoPerfilDefecto;

        IF @idPerfilEncontrado = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El perfil solicitado no existe en el sistema.',
                @mensajeTecnicoResultado = CONCAT('Fallo: No se encontró el código [', @codigoPerfilDefecto, '] en uv_perfil. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
        END
        ELSE
        BEGIN
            -- Éxito: El perfil existe
            SELECT 
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Perfil localizado exitosamente. ID: ', CAST(@idPerfilEncontrado AS NVARCHAR(50)))),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurrió un error inesperado al validar el perfil.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_perfil_existe_por_codigo_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO


