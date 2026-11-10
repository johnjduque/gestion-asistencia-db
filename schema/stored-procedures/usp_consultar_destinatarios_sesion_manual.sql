USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_manual (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + coordinadores).
-- Destinatarios del aviso de una sesion creada manualmente por el docente (uv_sesion_manual; una sesion no manual devuelve 0 filas):
--   * ESTUDIANTE:  matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo;
--   * COORDINADOR: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo). Un coordinador de dos
--                  programas del mismo grupo es UNA fila; un grupo mixto devuelve ambos coordinadores.
-- CULM-001 / DEC-065 (2): ademas devuelve la fila del DOCENTE titular (tipoDestinatario = 'DOCENTE', al final del orden) para que el backend
-- le avise la decision del coordinador; el aviso a la coordinacion al crear lo sigue dando la fila COORDINADOR.
-- Ambito: RBAC DOCENTE + titularidad 'SESION' dentro del SP (THROW 51000 con el mensaje tecnico si falla). El correo es de uso
-- interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs. Mismo formato que
-- usp_consultar_destinatarios_sesion_cancelada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_manual]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;

    -- Correlacion, ejecutor y sesion obligatorios, RBAC DOCENTE y titularidad 'SESION' (validacion compartida)
    EXEC dbo.usp_validar_docente_titular_sesion_interno
        @idSesion = @idSesion,
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

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
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = u.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g                 ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = sm.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario u               ON u.id = ei.idUsuario
        WHERE sm.idSesion = @idSesionDefecto

        UNION ALL

        SELECT  tipoDestinatario = CAST(N'COORDINADOR' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ci.idUsuario,
                nombreCompleto   = CAST(ci.nombreCompleto AS NVARCHAR(400)),
                correo           = ci.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        INNER JOIN (
            SELECT DISTINCT ci2.idUsuario, ci2.nombreCompleto, ci2.correo
            FROM dbo.ufn_programas_grupo(
                     (SELECT s.idGrupo FROM dbo.uv_sesion_manual s WHERE s.idSesion = @idSesionDefecto)) pg
            INNER JOIN dbo.Programa p                    ON p.id = pg.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad ci2  ON ci2.id = p.coordinador
                                                        AND ci2.estaActivoRolCoordinador = 1 AND ci2.estaActivoUsuario = 1
        ) ci ON 1 = 1
        WHERE sm.idSesion = @idSesionDefecto
        UNION ALL
        SELECT  tipoDestinatario = CAST(N'DOCENTE' AS NVARCHAR(20)),
                ordenTipo        = 3,
                idUsuario        = di.idUsuario,
                nombreCompleto   = CAST(di.nombreCompleto AS NVARCHAR(400)),
                correo           = ud.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
        WHERE sm.idSesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
