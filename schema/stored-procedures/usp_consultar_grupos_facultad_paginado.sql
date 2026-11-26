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
-- SKILLS-BD lote 5 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, TRY/CATCH de lectura y facultad del
-- decano por uv_facultad/uv_decano_identidad/uv_programa (antes, las tablas); mismo resultado y codigos.
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
    DECLARE @idFacultad UNIQUEIDENTIFIER;
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

        -- PASO 2: Resolver la facultad del decano y validar el programa del filtro
        IF @codigoRechazo IS NULL AND @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idFacultad = f.id FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
            WHERE di.idUsuario = @idUsuarioEjecutor ORDER BY f.id;
            IF @idFacultad IS NULL
            BEGIN
                SET @codigoRechazo = 'KPI_003';
            END
            ELSE IF @idPrograma IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idPrograma AND p.idFacultad = @idFacultad)
            BEGIN
                SET @codigoRechazo = 'KPI_003';
            END
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

        -- PASO 4: Consulta paginada de los grupos de la facultad
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
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
