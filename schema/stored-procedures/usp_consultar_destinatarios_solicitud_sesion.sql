USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_solicitud_sesion (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + docente).
-- Destinatarios del aviso de la DECISION del coordinador sobre una solicitud de sesion extraordinaria (aprobada o rechazada). Lo
-- consulta el coordinador (usp_consultar_destinatarios_sesion_manual es del docente titular):
--   * DOCENTE:    el docente titular del grupo (usuario activo), siempre;
--   * ESTUDIANTE: matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo; el backend los avisa solo cuando la
--                 solicitud fue aprobada.
-- Solo sesiones con solicitud (SesionSolicitud); una sesion sin solicitud devuelve 0 filas. Ambito: RBAC COORDINADOR + programa del
-- grupo (usp_validar_coordinador_sesion_interno; THROW 51000 con el mensaje tecnico si falla). Mismas 9 columnas que
-- usp_consultar_destinatarios_sesion_manual. El correo es de uso interno del NotificacionPort.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idGrupo UNIQUEIDENTIFIER;

    IF @idSesion IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  tipoDestinatario = x.tipoDestinatario,
            idUsuario        = x.idUsuario,
            nombreCompleto   = x.nombreCompleto,
            correo           = x.correo,
            nombreAsignatura = x.nombreAsignatura,
            nombreGrupo      = x.nombreGrupo,
            nombreDocente    = x.nombreDocente,
            fechaHoraInicio  = x.fechaHoraInicio,
            fechaHoraFin     = x.fechaHoraFin
    FROM (
        SELECT  tipoDestinatario = CAST(N'DOCENTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = di.idUsuario,
                nombreCompleto   = CAST(di.nombreCompleto AS NVARCHAR(400)),
                correo           = ud.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = s.fechaHoraInicio,
                fechaHoraFin     = s.fechaHoraFin
        FROM dbo.SesionSolicitud ss
        INNER JOIN dbo.Sesion s                ON s.id = ss.sesion
        INNER JOIN dbo.uv_grupo g              ON g.id = s.grupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
        WHERE ss.sesion = @idSesionDefecto
        UNION ALL
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = ue.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = s.fechaHoraInicio,
                fechaHoraFin     = s.fechaHoraFin
        FROM dbo.SesionSolicitud ss
        INNER JOIN dbo.Sesion s                   ON s.id = ss.sesion
        INNER JOIN dbo.uv_grupo g                 ON g.id = s.grupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ue              ON ue.id = ei.idUsuario
        WHERE ss.sesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
