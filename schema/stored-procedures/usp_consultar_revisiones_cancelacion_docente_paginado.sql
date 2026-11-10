USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_revisiones_cancelacion_docente_paginado (DEC-065 (1), HU026C; CONTRACT §2.5.7)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC DOCENTE. Revisiones de cancelacion por inasistencia de los
-- grupos donde el ejecutor es docente titular (uv_revision_cancelacion), en cualquier estado: el docente sigue la propuesta y la decision
-- del coordinador sin poder resolver. Mismas columnas que usp_consultar_revisiones_cancelacion_coordinador_paginado: uv_revision_cancelacion
-- + idPrograma, nombrePrograma, porcentajeActual, horasFaltaActual, horasDictadasActual, umbralPerdida, esResolutorActual (siempre 0),
-- accionesPermitidas (siempre vacio) y totalRegistros. @soloPendientes = revisiones que esperan la decision del docente (estado con
-- requiereAccionDocente, PENDIENTE_DOCENTE). Orden: fecha de cruce (creacion) DESC. @idGrupo que no es suyo -> SEC_002;
-- @estado inexistente -> RCN_002.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_docente_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @idCorrelacion  UNIQUEIDENTIFIER,
    @soloPendientes BIT = 1,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @estado         NVARCHAR(20) = NULL,
    @numeroPagina   INT = 1,
    @tamanoPagina   INT = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuario IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuario',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
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
    IF @estadoResultado = 1 AND @estado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstadoRevisionCancelacion e WHERE e.codigo = UPPER(TRIM(@estado)))
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_002', @p_param1 = @estado,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idGrupo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Grupo del docente',
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
        esResolutorActual = CAST(0 AS BIT),
        accionesPermitidas = CAST(N'' AS NVARCHAR(200)),
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_revision_cancelacion rv
    OUTER APPLY (
        SELECT TOP 1 idPrograma = p.id, p.nombre
        FROM dbo.EstudiantePrograma ep
        INNER JOIN dbo.ufn_programas_grupo(rv.idGrupo) pg ON pg.idPrograma = ep.programa
        INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
        WHERE ep.estudiante = rv.idEstudiante
        ORDER BY p.nombre ASC, p.id ASC
    ) x
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
    WHERE rv.idUsuarioDocenteTitular = @idUsuarioDefecto
      AND (@estado IS NULL OR rv.codigoEstado = UPPER(TRIM(@estado)))
      AND (@idGrupo IS NULL OR rv.idGrupo = @idGrupo)
      AND (@soloPendientes IS NULL OR @soloPendientes = 0 OR rv.requiereAccionDocente = 1)
    ORDER BY rv.fechaCreacionUtc DESC, rv.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
