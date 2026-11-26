USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cargar_dias_festivos (CULM-001 B.1; CONTRACT §2.7.4) — recarga de festivos por el ADMINISTRADOR.
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + anio, totalFestivos, festivosInsertados,
-- festivosActualizados, festivosDesactivados (NULL si estadoResultado = 0).
-- RBAC ADMINISTRADOR; la validacion y la escritura (transaccion propia o savepoint) las hace
-- usp_cargar_dias_festivos_interno. Los festivos son nacionales: no dependen de la institucion del administrador.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): comentarios PASO y BEGIN/END en todos los IF.
CREATE OR ALTER PROCEDURE [dbo].[usp_cargar_dias_festivos]
(
    @anio                     INT,
    @festivosJSON             NVARCHAR(MAX),
    @fuente                   NVARCHAR(40),
    @diferenciasCalculoLocal  INT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @insertados INT = 0, @actualizados INT = 0, @desactivados INT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar parametros obligatorios
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil ADMINISTRADOR del ejecutor
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Cargar los festivos del anio (nucleo interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_cargar_dias_festivos_interno
                @anio = @anio,
                @festivosJSON = @festivosJSON,
                @fuente = @fuente,
                @diferenciasCalculoLocal = @diferenciasCalculoLocal,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @festivosInsertados = @insertados OUTPUT,
                @festivosActualizados = @actualizados OUTPUT,
                @festivosDesactivados = @desactivados OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: Manejo de errores
        IF XACT_STATE() = -1 AND @@TRANCOUNT > 0
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- PASO 6: Resultado
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        anio                    = IIF(@estadoResultado = 1, @anio, NULL),
        totalFestivos           = IIF(@estadoResultado = 1, @insertados + @actualizados, NULL),
        festivosInsertados      = IIF(@estadoResultado = 1, @insertados, NULL),
        festivosActualizados    = IIF(@estadoResultado = 1, @actualizados, NULL),
        festivosDesactivados    = IIF(@estadoResultado = 1, @desactivados, NULL);
END;
GO
