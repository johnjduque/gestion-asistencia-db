USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_validar_tipo_identificacion_exista_por_id_interno]
(
    @idTipoId UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    -- 1. Estandarizaci?n del ID de correlaci?n e ID de entrada
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idTipoIdDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idTipoId, '00000000-0000-0000-0000-000000000000'))));

    -- Inicializaci?n de variables de salida
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
        
        -- 2. Validar que el ID no sea el vac?o (All zeros)
        IF @estadoResultado = 1 AND @idTipoIdDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT @mensajeUsuarioResultado = 'Debe seleccionar un tipo de identificaci?n v?lido.',
                   @mensajeTecnicoResultado = CONCAT('Fallo: @idTipoIdDefecto es el GUID vac?o. Correlaci?n: ', @idCorrelacionDefecto),
                   @estadoResultado = 0;
        END

        -- 3. Validaci?n de existencia en la VISTA uv_tipo_identificacion
        IF @estadoResultado = 1 AND NOT EXISTS (
            SELECT 1 
            FROM [dbo].[uv_tipo_identificacion] 
            WHERE id = @idTipoIdDefecto
        )
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El tipo de identificaci?n seleccionado no existe en el sistema.',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Fallo: No se encontr? el ID [', CAST(@idTipoIdDefecto AS NVARCHAR(50)), '] en uv_tipo_identificacion.')),
                @estadoResultado = 0;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurri? un error inesperado al validar el tipo de identificaci?n.',
            @mensajeTecnicoResultado = CONCAT('Error cr?tico en orquestador [usp_validar_tipo_identificacion_exista_por_id_interno]: ', ERROR_MESSAGE(), '. L?nea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
