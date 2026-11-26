USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_dias_festivos (CULM-001 B.1; CONTRACT §2.7.7, §3.2.2 GET /admin/festivos)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 ante validacion fallida).
-- RBAC ADMINISTRADOR. Filas de uv_dia_festivo del anio (solo activos salvo @incluirInactivos = 1) + datos de la
-- ultima carga del anio (uv_carga_dia_festivo.esUltimaCargaAnio = 1): fuenteUltimaCarga, fechaUltimaCargaUtc,
-- diferenciasCalculoLocal, y totalRegistros = COUNT(1) OVER(). El administrador ve y recarga, pero no edita.
-- Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO (PAG_001); anio fuera de
-- FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO: FES_001.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH de lectura que relanza (los rechazos siguen saliendo como THROW 51000); sin ISNULL (un IIF equivalente). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_dias_festivos]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @anio              INT,
    @incluirInactivos  BIT = 0,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @anioMinimo           INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MINIMO');
    DECLARE @anioMaximo           INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MAXIMO');
    DECLARE @incluir              BIT = IIF(@incluirInactivos IS NULL, 0, @incluirInactivos);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Anio dentro del rango parametrizado (FES_001)
        IF @estadoResultado = 1 AND (@anio IS NULL OR @anioMinimo IS NULL OR @anioMaximo IS NULL OR @anio < @anioMinimo OR @anio > @anioMaximo)
        BEGIN
            SET @p1 = IIF(@anio IS NULL, N'NULL', CONVERT(NVARCHAR(20), @anio));
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_001', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Paginacion (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 6: Rechazo: THROW 51000 con el mensaje tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 7: Pagina de festivos del anio con la ultima carga
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        SELECT
            id                      = df.id,
            fecha                   = df.fecha,
            anio                    = df.anio,
            nombre                  = df.nombre,
            fuente                  = df.fuente,
            estaActivo              = df.estaActivo,
            fechaCargaUtc           = df.fechaCargaUtc,
            idCorrelacionCarga      = df.idCorrelacionCarga,
            fuenteUltimaCarga       = uc.fuente,
            fechaUltimaCargaUtc     = uc.fechaCargaUtc,
            diferenciasCalculoLocal = uc.diferenciasCalculoLocal,
            totalRegistros          = COUNT(1) OVER()
        FROM dbo.uv_dia_festivo df
        OUTER APPLY (
            SELECT TOP 1 c.fuente, c.fechaCargaUtc, c.diferenciasCalculoLocal
            FROM dbo.uv_carga_dia_festivo c
            WHERE c.anio = df.anio AND c.esUltimaCargaAnio = 1
        ) uc
        WHERE df.anio = @anio
          AND (@incluir = 1 OR df.estaActivo = 1)
        ORDER BY df.fecha ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 8: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
