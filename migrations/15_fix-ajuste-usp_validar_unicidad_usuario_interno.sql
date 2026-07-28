USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_unicidad_usuario]    Script Date: 27/07/2026 11:58:00 p. m. ******/
DROP PROCEDURE [dbo].[usp_validar_unicidad_usuario]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_unicidad_usuario]    Script Date: 27/07/2026 11:58:00 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_unicidad_usuario_interno]
(
    @tipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @correo NVARCHAR(255),
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    -- 1. Estandarización de variables locales (Variables Defecto)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @tipoIdIdentificacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@tipoIdIdentificacion, '00000000-0000-0000-0000-000000000000'))));
    
    -- Corrección: El número es INT, se valida contra 0 como valor por defecto
    DECLARE @numeroIdentificacionDefecto INT = UPPER(LTRIM(RTRIM(ISNULL(@numeroIdentificacion, 0))));
    DECLARE @correoDefecto NVARCHAR(255) = LOWER(LTRIM(RTRIM(ISNULL(@correo,''))));

    -- Inicialización de variables de salida
    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar Unicidad por Documento de Identidad (Usando variables Defecto)
        IF @estadoResultado = 1 AND EXISTS (
            SELECT 1 
            FROM [dbo].[uv_usuario] 
            WHERE idTipoIdentificacion = @tipoIdIdentificacionDefecto 
              AND numeroIdentificacion = @numeroIdentificacionDefecto
        )
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'Ya existe un usuario registrado con este número de identificación.',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Fallo unicidad: Duplicado en idTipoIdentificacion [', CAST(@tipoIdIdentificacionDefecto AS NVARCHAR(50)), '] y numeroIdentificacion [', CAST(@numeroIdentificacionDefecto AS NVARCHAR(20)), '].')),
                @estadoResultado = 0;
        END

        -- 3. Validar Unicidad por Correo Electrónico (Usando variables Defecto)
        IF @estadoResultado = 1 AND EXISTS (
            SELECT 1 
            FROM [dbo].[uv_usuario] 
            WHERE correo = @correoDefecto
        )
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'La dirección de correo electrónico ya se encuentra registrada.',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Fallo unicidad: El correo [', @correoDefecto, '] ya existe en uv_usuario.')),
                @estadoResultado = 0;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurrió un error al verificar la disponibilidad de los datos del usuario.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_unicidad_usuario_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO


