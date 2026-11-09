USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_aforo_grupos_facultad (HU144). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Aforo = matriculados activos / cupo maximo (D4); NULL si el cupo es 0. No se recorta por encima de 100 %.
-- @soloHabilitados = 1 (defecto) lista solo grupos habilitados en su periodo. Orden: aforo descendente (NULL al final).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_aforo_grupos_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @soloHabilitados    BIT              = 1
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idFacultad = @idFacultad OUTPUT;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 2: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;

    -- PASO 3: Validacion de negocio (usp_validar_programa_en_facultad_interno)
    IF @idPrograma IS NOT NULL
        EXEC dbo.usp_validar_programa_en_facultad_interno @idFacultad = @idFacultad, @idPrograma = @idPrograma;
    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        programas = p.nombrePrograma,
        cupoMaximo = g.capacidadMaximaPermitida,
        matriculadosActivos = g.estudiantesActivos,
        cuposDisponibles = g.cuposDisponibles,
        tasaAforo = CAST(IIF(ISNULL(g.capacidadMaximaPermitida, 0) = 0, NULL, 100.0 * g.estudiantesActivos / g.capacidadMaximaPermitida) AS DECIMAL(7,2)),
        grupoEstaHabilitado = CAST(g.grupoEstaHablitado AS BIT),
        totalRegistros = COUNT(*) OVER()
    -- CULM-001 B2NM (R5): 1 fila por grupo; idPrograma/nombrePrograma = primer programa del ambito, nombrePrograma lista todos.
    FROM dbo.uv_grupo g
    CROSS APPLY (SELECT TOP 1 id = x.id,
                              nombrePrograma = (SELECT STRING_AGG(y.nombrePrograma, N', ') WITHIN GROUP (ORDER BY y.nombrePrograma)
                                                FROM dbo.uv_grupo_programa gy
                                                INNER JOIN dbo.uv_programa y ON y.id = gy.idPrograma
                                                WHERE gy.idGrupo = g.id AND y.idFacultad = @idFacultad)
                 FROM dbo.uv_grupo_programa gp
                 INNER JOIN dbo.uv_programa x ON x.id = gp.idPrograma
                 WHERE gp.idGrupo = g.id AND x.idFacultad = @idFacultad AND (@idPrograma IS NULL OR x.id = @idPrograma)
                 ORDER BY x.nombrePrograma, x.id) p
    WHERE g.idPeriodoAcademico = @idPeriodo
      AND (ISNULL(@soloHabilitados, 1) = 0 OR g.grupoEstaHablitado = 1)
    ORDER BY IIF(ISNULL(g.capacidadMaximaPermitida, 0) = 0, 1, 0) ASC,
             100.0 * g.estudiantesActivos / NULLIF(g.capacidadMaximaPermitida, 0) DESC,
             g.codigo ASC, g.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
