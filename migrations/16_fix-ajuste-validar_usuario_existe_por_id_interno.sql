USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_usuario_existe_por_id]    Script Date: 28/07/2026 12:25:37 a. m. ******/
DROP PROCEDURE [dbo].[usp_validar_usuario_existe_por_id]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_usuario_existe_por_id]    Script Date: 28/07/2026 12:25:37 a. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_usuario_existe_por_id_interno]
(
    @idUsuario UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    -- 1. Estandarización de variables locales
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idUsuarioDefecto UNIQUEIDENTIFIER = ISNULL(@idUsuario, '00000000-0000-0000-0000-000000000000');

    -- Inicialización de variables de respuesta
    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        
        -- 2. Validación de GUID vacío (Opcional pero recomendado)
        IF @estadoResultado = 1 AND @idUsuarioDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El identificador de usuario no es válido.',
                @mensajeTecnicoResultado = CONCAT('Fallo: @idUsuario es el GUID vacío. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Validación de Existencia y Estado en la VISTA uv_usuario
        DECLARE @existe BIT = 0;
        DECLARE @activo BIT = 0;

        SELECT TOP 1 
            @existe = 1,
            @activo = estaActivoUsuario
        FROM [dbo].[uv_usuario]
        WHERE id = @idUsuarioDefecto;

        -- Regla: Debe existir
        IF @existe = 0
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El usuario especificado no existe en el sistema.',
                @mensajeTecnicoResultado = CONCAT('Fallo: ID [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), '] no encontrado en uv_usuario. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
        END
        -- Regla: Debe estar activo
        ELSE IF @activo = 0
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El usuario se encuentra inactivo y no puede realizar esta operación.',
                @mensajeTecnicoResultado = CONCAT('Fallo: Usuario [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), '] tiene estaActivoUsuario = 0. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
        END
        ELSE
        BEGIN
            -- Éxito total
            SELECT 
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Orquestador finalizado para Usuario: ', @idUsuario, ' validado correctamente')),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar la información del usuario.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_usuario_existe_por_id_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO


