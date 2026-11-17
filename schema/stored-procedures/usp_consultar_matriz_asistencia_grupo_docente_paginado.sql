USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_matriz_asistencia_grupo_docente_paginado (CIERRE-W3M, punto 1; DEC-066)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, GRU_*, SEC_002). RBAC DOCENTE titular del grupo (el ambito se valida antes de leer filas).
-- Matriz estudiantes x sesiones del grupo ya cruzada en la base: una pagina de matriculas (orden nombreCompletoEstudiante,
-- idEstudiante, el mismo de usp_consultar_resumen_asistencia_grupo_docente_paginado) y, por cada una, una fila por sesion del
-- grupo (orden numero) con el estado que define uv_asistencia_sesion_horas (tramos entre tomas, DEC-066). @busqueda (opcional,
-- subcadena del nombre o del documento) y la paginacion se aplican a ESTUDIANTES; totalRegistros es el total filtrado de
-- estudiantes (no de celdas). Sin sesiones: una fila por estudiante con idSesion NULL.
-- Celda: codigoEstado = NO_DISPONIBLE (sesion cancelada), SIN_REGISTRO (sin cabecera de asistencia) o el
-- codigoEstadoSesionEstudiante de la vista (PRESENTE, AUSENTE, JUSTIFICADA, PARCIAL, NO_DISPONIBLE); minutosAsistidos y
-- minutosSesion salen de la misma vista.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_matriz_asistencia_grupo_docente_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50,
    @busqueda          NVARCHAR(100) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @busquedaFiltro       NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_grupo_exista_por_id_interno
            @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idGrupoDefecto, @tipoEntidadPadre = 'GRUPO',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    WITH alumnos AS (
        SELECT
            idEstudianteGrupo        = eg.id,
            idEstudiante             = eg.idEstudiante,
            nombreCompletoEstudiante = eg.nombreCompletoEstudiante,
            documento                = CAST(ei.numeroIdentificacion AS NVARCHAR(20)),
            codigoEstadoEstudiante   = eg.codigoEstadoEstudiante,
            totalRegistros           = COUNT(1) OVER()
        FROM dbo.uv_estudiante_grupo eg
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
        WHERE eg.idGrupo = @idGrupoDefecto
          AND (@busquedaFiltro IS NULL
               OR CHARINDEX(@busquedaFiltro, ei.nombreCompleto) > 0
               OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), ei.numeroIdentificacion)) > 0)
        ORDER BY eg.nombreCompletoEstudiante ASC, eg.idEstudiante ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY
    )
    SELECT
        idEstudianteGrupo        = a.idEstudianteGrupo,
        idEstudiante             = a.idEstudiante,
        nombreCompletoEstudiante = a.nombreCompletoEstudiante,
        documento                = a.documento,
        codigoEstadoEstudiante   = a.codigoEstadoEstudiante,
        totalRegistros           = a.totalRegistros,
        idSesion                 = s.idSesion,
        codigoEstado             = CAST(CASE WHEN s.idSesion IS NULL THEN NULL
                                             WHEN s.estaCancelada = 1 THEN N'NO_DISPONIBLE'
                                             WHEN h.idAsistencia IS NULL THEN N'SIN_REGISTRO'
                                             ELSE h.codigoEstadoSesionEstudiante END AS NVARCHAR(20)),
        minutosAsistidos         = CASE WHEN s.idSesion IS NULL THEN NULL ELSE ISNULL(h.minutosAsistidos, 0) END,
        minutosSesion            = CASE WHEN s.idSesion IS NULL THEN NULL
                                        ELSE IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin), 0) END
    FROM alumnos a
    LEFT JOIN dbo.uv_sesion_estado s ON s.idGrupo = @idGrupoDefecto
    LEFT JOIN dbo.uv_asistencia_sesion_horas h
           ON h.idEstudianteGrupo = a.idEstudianteGrupo AND h.idSesion = s.idSesion AND h.idGrupo = @idGrupoDefecto
    ORDER BY a.nombreCompletoEstudiante ASC, a.idEstudiante ASC, s.numero ASC, s.idSesion ASC;
END;
GO
