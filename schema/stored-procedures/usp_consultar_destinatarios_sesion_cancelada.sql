USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_cancelada (CULM-001 B.1, HU047; CONTRACT §2.7.3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo).
-- Destinatarios de la notificacion SESION_CANCELADA: las matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo de
-- la sesion, solo si la sesion esta cancelada (si no, 0 filas). RBAC DOCENTE + titularidad 'SESION' dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Mismo formato que usp_consultar_destinatarios_reclamo_asistencia: el
-- correo es de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
-- SKILLS-BD lote 13 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* y
-- TRY/CATCH de lectura que relanza (READ_QUERY_RESULTSET). Mismas columnas y mismas filas.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_cancelada]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion, ejecutor y sesion obligatorios, RBAC DOCENTE y titularidad 'SESION' (validacion compartida)
        EXEC dbo.usp_validar_docente_titular_sesion_interno
            @idSesion = @idSesion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 3: estudiantes activos del grupo de la sesion cancelada
        SELECT
            idEstudiante      = eg.idEstudiante,
            idUsuario         = ei.idUsuario,
            nombreCompleto    = CAST(ei.nombreCompleto AS NVARCHAR(400)),
            correo            = u.correo,
            nombreAsignatura  = g.nombreAsignatura,
            nombreGrupo       = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
            nombreDocente     = CAST(di.nombreCompleto AS NVARCHAR(400)),
            fechaHoraInicio   = se.fechaHoraInicio,
            fechaHoraFin      = se.fechaHoraFin,
            motivoCancelacion = se.motivoCancelacion
        FROM dbo.uv_sesion_estado se
        INNER JOIN dbo.uv_grupo g               ON g.id = se.idGrupo
        INNER JOIN dbo.uv_docente_identidad di  ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg   ON eg.idGrupo = se.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
        INNER JOIN dbo.uv_usuario u             ON u.id = ei.idUsuario
        WHERE se.idSesion = @idSesionDefecto
          AND se.estaCancelada = 1
        ORDER BY ei.nombreCompleto, eg.idEstudiante;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
