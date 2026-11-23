USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_ejecutor_administrador_periodo_interno]   (INTERNO)
-- DEC-081: preambulo comun de usp_crear_receso_academico y usp_retirar_receso_academico (la primera validacion que falla corta):
--   PASO 1: correlacion presente (usp_validar_id_correlacion_esta_presente_interno).
--   PASO 2: ejecutor obligatorio (GEN_002); se evalua con el @idUsuarioEjecutor ORIGINAL (antes de aplicar el valor por defecto).
--   PASO 3: ambito del ejecutor, ADMINISTRADOR de la institucion (usp_resolver_institucion_gestor_periodo_interno: SEC_001 si no es
--           administrador, PER_005 si no tiene institucion); deja la institucion en @idInstitucion.
-- @idCorrelacion llega ya resuelto con su valor por defecto. Los mensajes de entrada se conservan hasta que un paso los escribe, y
-- @estadoResultado parte de 1 (no se inicializa aqui: lo fija el PASO 1). Sin transaccion propia ni TRY/CATCH: un error del sistema sube
-- al CATCH del SP publico que lo llama. Sin EXECUTE para el rol runtime.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_ejecutor_administrador_periodo_interno]
(
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idInstitucion           UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;
    SET @idInstitucion = NULL;

    -- PASO 1: correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del ejecutor (ADMINISTRADOR de la institucion)
    IF @estadoResultado = 1
        EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
            @idUsuario = @idUsuarioEjecutorDefecto, @idCorrelacion = @idCorrelacion,
            @idInstitucion = @idInstitucion OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
END;
GO
