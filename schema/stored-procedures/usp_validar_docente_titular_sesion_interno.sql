USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_docente_titular_sesion_interno (CULM-001; HU047)
--
-- Validacion compartida por las consultas de destinatarios que hace el docente sobre una sesion suya
-- (usp_consultar_destinatarios_sesion_cancelada y usp_consultar_destinatarios_sesion_manual). Mantiene en un unico punto:
--   * correlacion presente;
--   * ejecutor y sesion obligatorios (GEN_002);
--   * RBAC DOCENTE (SEC_001);
--   * titularidad jerarquica del docente sobre la sesion (tipo 'SESION').
-- No escribe, no abre transacciones y no lanza: devuelve el resultado en los parametros de salida y el llamador decide
-- (las consultas de lectura lanzan THROW 51000 con el mensaje tecnico). No se concede al rol runtime: se usa por
-- encadenamiento de propiedad desde los SP publicos.
-- ============================================================================
-- SKILLS-BD lote 13 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH que relanza el error al
-- llamador (antes, sin TRY: mismo flujo). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_titular_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @correlacion UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @docente     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @sesion      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    -- PASO 0: inicializacion de las salidas desde el catalogo
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @correlacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor y sesion obligatorios
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idSesion IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idSesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @correlacion);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC DOCENTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @docente,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @correlacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: titularidad jerarquica sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @docente,
                @idEntidadPadre = @sesion,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @correlacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: el error se propaga igual al llamador (sin triplete propio, como antes)
        THROW;
    END CATCH
END;
GO
