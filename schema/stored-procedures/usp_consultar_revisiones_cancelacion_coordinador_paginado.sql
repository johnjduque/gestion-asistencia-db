USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_revisiones_cancelacion_coordinador_paginado (CULM-001 C.1; CONTRACT §2.5.7, SUPUESTO-C-14, DEC-020/031)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC COORDINADOR. Revisiones de estudiantes con
-- EstudiantePrograma en un programa vigente del grupo que este en ufn_programas_coordinador(ejecutor): en un grupo mixto el
-- coordinador de un programa no ve a los del otro. Una fila por revision (programa de menor nombre). Filas: uv_revision_cancelacion +
-- idPrograma, nombrePrograma, porcentajeActual, horasFaltaActual, horasDictadasActual, umbralPerdida, esResolutorActual,
-- accionesPermitidas (solo si es resolutor y la matricula esta activa), totalRegistros.
-- @idPrograma ajeno -> COO_003; @idGrupo sin programa comun -> SEC_002; @codigoEstado inexistente -> RCN_002.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_coordinador_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20,
    @soloPendientes    BIT = 0,
    @codigoEstado      NVARCHAR(20) = NULL,
    @idPrograma        UNIQUEIDENTIFIER = NULL,
    @idGrupo           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @codigoEstado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstadoRevisionCancelacion e WHERE e.codigo = UPPER(TRIM(@codigoEstado)))
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_002', @p_param1 = @codigoEstado,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioDefecto) pc WHERE pc.idPrograma = @idPrograma)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'COO_003',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idGrupo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg INNER JOIN dbo.ufn_programas_coordinador(@idUsuarioDefecto) pc ON pc.idPrograma = pg.idPrograma)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Grupo del programa',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        rv.*,
        idPrograma = x.idPrograma,
        nombrePrograma = x.nombre,
        porcentajeActual = rs.porcentajeInasistencia,
        horasFaltaActual = rs.horasFalta,
        horasDictadasActual = rs.horasDictadas,
        umbralPerdida = rs.umbralPerdida,
        esResolutorActual = CAST(res.esResolutor AS BIT),
        accionesPermitidas = CASE WHEN res.esResolutor = 1 AND rv.codigoEstadoMatricula = @codigoInscrita THEN ISNULL(acc.acciones, N'') ELSE N'' END,
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_revision_cancelacion rv
    CROSS APPLY (
        SELECT TOP 1 idPrograma = p.id, p.nombre
        FROM dbo.EstudiantePrograma ep
        INNER JOIN dbo.ufn_programas_grupo(rv.idGrupo) pg ON pg.idPrograma = ep.programa
        INNER JOIN dbo.ufn_programas_coordinador(@idUsuarioDefecto) pc ON pc.idPrograma = pg.idPrograma
        INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
        WHERE ep.estudiante = rv.idEstudiante AND (@idPrograma IS NULL OR p.id = @idPrograma)
        ORDER BY p.nombre ASC, p.id ASC
    ) x
    OUTER APPLY (
        SELECT esResolutor = CAST(IIF(EXISTS (SELECT 1 FROM dbo.ufn_revision_cancelacion_resolutores(rv.idEstudianteGrupo, rv.idUsuarioDecisionDocente) f WHERE f.idUsuario = @idUsuarioDefecto), 1, 0) AS BIT)
    ) res
    OUTER APPLY (
        SELECT acciones = STRING_AGG(t.codigoDecision, N',') WITHIN GROUP (ORDER BY t.codigoDecision DESC)
        FROM dbo.TransicionRevisionCancelacion t WHERE t.estadoOrigen = rv.idEstado AND t.esDecisionResolutor = 1
    ) acc
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
    WHERE (@codigoEstado IS NULL OR rv.codigoEstado = UPPER(TRIM(@codigoEstado)))
      AND (@idGrupo IS NULL OR rv.idGrupo = @idGrupo)
      AND (@soloPendientes IS NULL OR @soloPendientes = 0 OR (rv.requiereAccionResolutor = 1 AND res.esResolutor = 1))
    ORDER BY res.esResolutor DESC, rv.requiereAccionResolutor DESC, rv.fechaDecisionDocenteUtc ASC, rv.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
