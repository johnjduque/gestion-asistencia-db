USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (DEC-019): malla de un plan (coordinador y decano). 1 fila por vinculo activo de la tabla puente.
-- Plan inexistente o fuera del ambito (coordinador: sus programas; decano: su facultad) -> PLA_002 (404).
-- compartida = 1 si la asignatura tiene vinculos activos en mas de un programa. Paginado con COUNT(*) OVER().
-- =============================================================================
-- SKILLS-BD lote 6 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, TRY/CATCH de lectura y ambito del plan
-- por uv_plan_estudio (antes, la tabla); mismo resultado y codigos.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_plan_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idPlanEstudio     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @numeroSemestre    INT = NULL,
    @codigoCaracter    NVARCHAR(3) = NULL,
    @busqueda          NVARCHAR(100) = NULL
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
    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion y el ejecutor
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            SET @codigoRechazo = 'VAL_001';
        END

        -- PASO 2: Validar el ambito del ejecutor
        IF @codigoRechazo IS NULL AND @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_plan_estudio pe
                           WHERE pe.id = @idPlanEstudio
                             AND (pe.idPrograma IN (SELECT idPrograma FROM dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor))))
        BEGIN
            SET @codigoRechazo = 'PLA_002';
        END

        -- PASO 3: Rechazar con el mensaje del catalogo
        IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
        BEGIN
            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: Consulta y retorno de resultados
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
            horasSemanales        = v.horasSemanales,   -- SES-GEN-01: NULL = sin cargar
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_asignatura_plan_estudio v
        WHERE v.idPlanEstudio = @idPlanEstudio
          AND v.estaActivoVinculo = 1
          AND (@numeroSemestre IS NULL OR v.numeroSemestre = @numeroSemestre)
          AND (NULLIF(TRIM(@codigoCaracter), N'') IS NULL OR v.codigoCaracter = TRIM(@codigoCaracter))
          AND (@patron IS NULL OR UPPER(v.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(v.codigoAsignatura) LIKE @patron ESCAPE N'\')
        ORDER BY v.numeroSemestre ASC, v.nombreAsignatura ASC, v.codigoAsignatura ASC, v.idAsignatura ASC
        OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
