USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (DEC-019, F-DEC-002): grupos de la facultad del decano (reemplaza GrupoJpaRepository.HQL_GRUPOS_POR_FACULTAD).
-- Ambito por EXISTS sobre uv_grupo_programa: 1 fila por grupo con programas = nombres de los programas del grupo en su facultad.
-- @idPrograma fuera de su facultad -> KPI_003 (403). Solo DECANO con facultad; si no, KPI_003.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @busqueda           NVARCHAR(100) = NULL
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

    DECLARE @idFacultad UNIQUEIDENTIFIER;
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
    BEGIN
        SELECT TOP 1 @idFacultad = f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE d.usuario = @idUsuarioEjecutor ORDER BY f.id;
        IF @idFacultad IS NULL
            SET @codigoRechazo = 'KPI_003';
        ELSE IF @idPrograma IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Programa p WHERE p.id = @idPrograma AND p.facultad = @idFacultad)
            SET @codigoRechazo = 'KPI_003';
    END

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
        idGrupo                  = g.id,
        codigo                   = g.codigo,
        nombre                   = g.nombre,
        idPeriodoAcademico       = g.idPeriodoAcademico,
        idAsignatura             = g.idAsignatura,
        nombreAsignatura         = g.nombreAsignatura,
        idDocente                = g.idDocente,
        capacidadMaximaPermitida = g.capacidadMaximaPermitida,
        estudiantesActivos       = g.estudiantesActivos,
        cuposDisponibles         = g.cuposDisponibles,
        grupoEstaHablitado       = g.grupoEstaHablitado,
        programas                = CAST((SELECT STRING_AGG(p.nombrePrograma, N', ') WITHIN GROUP (ORDER BY p.nombrePrograma)
                                         FROM dbo.uv_grupo_programa gp
                                         INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                                         WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad) AS NVARCHAR(1000)),
        totalRegistros           = COUNT(*) OVER()
    FROM dbo.uv_grupo g
    WHERE EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                  WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad AND (@idPrograma IS NULL OR p.id = @idPrograma))
      AND (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
      AND (@patron IS NULL OR UPPER(g.nombre) LIKE @patron ESCAPE N'\' OR UPPER(g.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(CAST(g.codigo AS NVARCHAR(20))) LIKE @patron ESCAPE N'\')
    ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO
