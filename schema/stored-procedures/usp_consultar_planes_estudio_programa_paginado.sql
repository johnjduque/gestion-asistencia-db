USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (DEC-019): planes de estudio de los programas del coordinador, con totales por la tabla puente (vinculos activos).
-- Reemplaza PlanEstudioJpaRepository.HQL_POR_PROGRAMA / HQL_TOTAL_SEMESTRES / totales de malla. @idPrograma ajeno -> COO_003.
-- =============================================================================
-- SKILLS-BD lote 6 (2026-11-26): PASO n, IF con BEGIN/END y TRY/CATCH de lectura; mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_planes_estudio_programa_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @idPrograma        UNIQUEIDENTIFIER = NULL,
    @estaActivo        BIT = NULL
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
        IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @idPrograma IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
        BEGIN
            SET @codigoRechazo = 'COO_003';
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
            idPlanEstudio         = pe.id,
            idPrograma            = pe.idPrograma,
            nombrePrograma        = pe.nombrePrograma,
            inp                   = pe.inp,
            estaActivoPlanEstudio = pe.estaActivoPlanEstudio,
            estaActivoTextoPlanEstudio = pe.estaActivoTextoPlanEstudio,
            justificacionEstado   = pe.justificacionEstado,
            totalSemestres        = ISNULL((SELECT MAX(sp.numeroSemestre) FROM dbo.uv_semestre_plan_estudio sp WHERE sp.idPlanEstudio = pe.id), 0),   -- ISNULL sobre agregacion (permitido)
            totalAsignaturas      = (SELECT COUNT(*) FROM dbo.uv_asignatura_plan_estudio v WHERE v.idPlanEstudio = pe.id AND v.estaActivoVinculo = 1),
            totalCreditos         = ISNULL((SELECT SUM(v.credito) FROM dbo.uv_asignatura_plan_estudio v WHERE v.idPlanEstudio = pe.id AND v.estaActivoVinculo = 1), 0),   -- ISNULL sobre agregacion (permitido)
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_plan_estudio pe
        WHERE pe.idPrograma IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE @idPrograma IS NULL OR cp.idPrograma = @idPrograma)
          AND (@estaActivo IS NULL OR pe.estaActivoPlanEstudio = @estaActivo)
        ORDER BY pe.nombrePrograma ASC, pe.inp ASC, pe.id ASC
        OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
