USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_carga_festivos_anio (CULM-001 B.1; CONTRACT §2.7.7, §3.4 punto 5)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET de una fila, sin usuario (lo usa el job
-- CargaFestivosScheduler para decidir si un anio falta por cargar): anio, totalActivos (0 si no hay carga),
-- fuenteUltimaCarga y fechaUltimaCargaUtc (NULL si no hay carga). THROW 51000 si falta la correlacion o el anio.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH de lectura que relanza (los rechazos siguen saliendo como THROW 51000). Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_carga_festivos_anio]
(
    @anio          INT,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
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

        -- PASO 2: Anio obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @anio IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'anio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Rechazo: THROW 51000 con el mensaje tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: Activos del anio y ultima carga
        SELECT
            anio                = @anio,
            totalActivos        = (SELECT COUNT(1) FROM dbo.uv_dia_festivo df WHERE df.anio = @anio AND df.estaActivo = 1),
            fuenteUltimaCarga   = uc.fuente,
            fechaUltimaCargaUtc = uc.fechaCargaUtc
        FROM (SELECT x = 1) base
        OUTER APPLY (
            SELECT TOP 1 c.fuente, c.fechaCargaUtc
            FROM dbo.uv_carga_dia_festivo c
            WHERE c.anio = @anio AND c.esUltimaCargaAnio = 1
        ) uc;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
