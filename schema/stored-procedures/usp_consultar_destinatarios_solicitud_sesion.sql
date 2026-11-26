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
-- SKILLS-BD lote 13 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (solicitud y sesion por uv_solicitud_sesion_registro y uv_sesion_registro) y
-- TRY/CATCH de lectura que relanza (READ_QUERY_RESULTSET). Mismas columnas y mismas filas.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idGrupo UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: sesion obligatoria
        IF @idSesion IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idSesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: coordinador responsable de la sesion (RBAC y ambito)
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

        -- PASO 3: rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: docente y estudiantes activos de la sesion solicitada
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
            FROM dbo.uv_solicitud_sesion_registro ss
            INNER JOIN dbo.uv_sesion_registro s    ON s.id = ss.idSesion
            INNER JOIN dbo.uv_grupo g              ON g.id = s.idGrupo
            INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
            INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
            WHERE ss.idSesion = @idSesionDefecto
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
            FROM dbo.uv_solicitud_sesion_registro ss
            INNER JOIN dbo.uv_sesion_registro s       ON s.id = ss.idSesion
            INNER JOIN dbo.uv_grupo g                 ON g.id = s.idGrupo
            INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
            INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = s.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
            INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
            INNER JOIN dbo.uv_usuario ue              ON ue.id = ei.idUsuario
            WHERE ss.idSesion = @idSesionDefecto
        ) x
        ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
