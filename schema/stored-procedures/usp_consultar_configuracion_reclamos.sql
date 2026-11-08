USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_configuracion_reclamos  (CULM-001 D.2, HU015; CONTRACT §3.2 GET /api/v1/configuracion/reclamos)
--
-- Clasificacion (DB-GP-001C): NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 ante validacion fallida).
-- Una fila con la configuracion institucional del formulario de reclamos para que el cliente no la duplique:
--   maximoSoportes          ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO
--   tamanioMaximoBytes      ARCHIVO/TAMANIO_MAXIMO_BYTES
--   tiposPermitidos         ARCHIVO/TIPOS_PERMITIDOS (tipos de contenido separados por coma)
--   limiteSubidasPorMinuto  ARCHIVOS/LIMITE_SUBIDAS_POR_MINUTO
--   diasLimiteJustificacion ASISTENCIA/DIAS_LIMITE_JUSTIFICACION
-- RBAC: ESTUDIANTE o DOCENTE (el docente ve los mismos limites que aplican al estudiante). Sin escrituras ni transacciones.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_configuracion_reclamos]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'ESTUDIANTE,DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        maximoSoportes          = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO'),
        tamanioMaximoBytes      = CAST(TRY_CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'TAMANIO_MAXIMO_BYTES') AS NVARCHAR(40)) AS BIGINT),
        tiposPermitidos         = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'TIPOS_PERMITIDOS') AS NVARCHAR(500)),
        limiteSubidasPorMinuto  = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'LIMITE_SUBIDAS_POR_MINUTO'),
        diasLimiteJustificacion = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
END;
GO
