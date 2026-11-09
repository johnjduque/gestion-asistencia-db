USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (DEC-019): asignaturas de los programas del coordinador (reemplaza AsignaturaJpaRepository.HQL_POR_PROGRAMA).
-- 1 fila por (asignatura, plan de sus programas). @idPrograma ajeno -> COO_003 (403); sin @idPrograma incluye todos sus programas (S4).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_coordinador_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @idPrograma        UNIQUEIDENTIFIER = NULL,
    @busqueda          NVARCHAR(100) = NULL,
    @estaActiva        BIT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
        SET @codigoRechazo = 'COO_003';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idAsignatura          = v.idAsignatura,
        codigo                = v.codigoAsignatura,
        nombre                = v.nombreAsignatura,
        credito               = v.credito,
        idArea                = v.idArea,
        nombreArea            = v.nombreArea,
        idComponente          = v.idComponente,
        nombreComponente      = v.nombreComponente,
        idPlanEstudio         = v.idPlanEstudio,
        inpPlanEstudio        = v.inpPlanEstudio,
        idPrograma            = v.idPrograma,
        nombrePrograma        = v.nombrePrograma,
        idSemestrePlanEstudio = v.idSemestrePlanEstudio,
        numeroSemestre        = v.numeroSemestre,
        codigoSemestre        = v.codigoSemestre,
        codigoCaracter        = v.codigoCaracter,
        nombreCaracter        = v.nombreCaracter,
        estaActivoVinculo     = v.estaActivoVinculo,
        estaActivaAsignatura  = v.estaActivaAsignatura,
        compartida            = CAST(IIF(v.totalProgramasActivos > 1, 1, 0) AS BIT),
        totalRegistros        = COUNT(*) OVER()
    FROM dbo.uv_asignatura_plan_estudio v
    WHERE v.estaActivoVinculo = 1
      AND v.idPrograma IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE @idPrograma IS NULL OR cp.idPrograma = @idPrograma)
      AND (@estaActiva IS NULL OR v.estaActivaAsignatura = @estaActiva)
      AND (@patron IS NULL OR UPPER(v.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(v.codigoAsignatura) LIKE @patron ESCAPE N'\')
    ORDER BY v.nombrePrograma ASC, v.numeroSemestre ASC, v.nombreAsignatura ASC, v.idAsignatura ASC, v.idPlanEstudio ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO
