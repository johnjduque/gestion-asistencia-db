USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_validar_perfil_existe_por_codigo_interno]
(
    @codigoPerfil NVARCHAR(10),
    @idCorrelacion UNIQUEIDENTIFIER,
    @idPerfilEncontrado UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS


    -- 1. Estandarizaci??n de variables locales
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @codigoPerfilDefecto NVARCHAR(10) = UPPER(LTRIM(RTRIM(ISNULL(@codigoPerfil, ''))));

    -- Inicializaci??n de variables de salida
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
       
        -- 2. Validaci??n de entrada (C??digo vac??o)
        IF @codigoPerfilDefecto = ''
        BEGIN
        
            SELECT 
                @mensajeUsuarioResultado = 'El c??digo de perfil no puede estar vac??o.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @codigoPerfil es nulo o vac??o. Correlaci??n: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. B??squeda y Validaci??n de existencia en la VISTA uv_perfil
        SELECT TOP 1 
            @idPerfilEncontrado = id 
        FROM [dbo].[uv_perfil] 
        WHERE codigo = @codigoPerfilDefecto;

        IF @idPerfilEncontrado = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El perfil solicitado no existe en el sistema.',
                @mensajeTecnicoResultado = CONCAT('Fallo: No se encontr?? el c??digo [', @codigoPerfilDefecto, '] en uv_perfil. Correlaci??n: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
        END
        ELSE
        BEGIN
            -- ??xito: El perfil existe
            SELECT 
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Perfil localizado exitosamente. ID: ', CAST(@idPerfilEncontrado AS NVARCHAR(50)))),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurri?? un error inesperado al validar el perfil.',
            @mensajeTecnicoResultado = CONCAT('Error cr??tico en orquestador [usp_validar_perfil_existe_por_codigo_interno]: ', ERROR_MESSAGE(), '. L??nea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
