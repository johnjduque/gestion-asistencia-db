USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 D.9-a (CONTRACT D §11.1/§11.2, F-ADM-030): periodos academicos de la institucion del ADMINISTRADOR, paginados, con
-- esVigente = 1 cuando la fecha local de hoy (TIEMPO/ZONA_HORARIA_SQLSERVER) esta entre fechaInicio y fechaFin (ambas inclusive).
-- Perfil e institucion los resuelve usp_resolver_institucion_gestor_periodo_interno (SEC_001 si no es administrador; PER_005 si no
-- tiene institucion activa). Tamano de pagina entre 1 y PAGINACION/TAMANO_MAXIMO (PAG_001). Las fallas se propagan con THROW.
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_periodos_academicos_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @zona NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
    DECLARE @hoy DATE;
    DECLARE @idInstitucion UNIQUEIDENTIFIER;
    DECLARE @offset INT;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = N'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001', @p_param1 = @numeroPagina, @p_param2 = @tamanoPagina,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
        EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
            @idUsuario = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacionDefecto,
            @idInstitucion = @idInstitucion OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @hoy = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE);
    SET @offset = (@numeroPagina - 1) * @tamanoPagina;

    SELECT
        id                = pa.id,
        idInstitucion     = pa.idInstitucion,
        nombreInstitucion = pa.nombreInstitucion,
        nombre            = pa.nombre,
        codigo            = pa.codigo,
        fechaInicio       = pa.fechaInicio,
        fechaFin          = pa.fechaFin,
        anio              = pa.anio,
        esVigente         = CAST(IIF(pa.fechaInicio <= @hoy AND pa.fechaFin >= @hoy, 1, 0) AS BIT),
        totalRegistros    = COUNT(1) OVER()
    FROM dbo.uv_periodo_academico pa
    WHERE pa.idInstitucion = @idInstitucion
    ORDER BY pa.fechaInicio DESC, pa.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
