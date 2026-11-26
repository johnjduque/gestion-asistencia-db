USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_receso_academico (DEC-081) — READ_QUERY_RESULTSET sin paginacion.
-- Destinatarios del aviso de un receso: una fila por (persona, sesion cancelada por ese receso), para que el backend agrupe y envie UN
-- correo por persona. Estudiantes: matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo de cada sesion; docentes: el titular del grupo.
-- Solo el ADMINISTRADOR de la institucion del periodo (usp_resolver_institucion_gestor_periodo_interno); receso inexistente, retirado o de
-- otra institucion => REC_009. Las fallas se propagan con THROW 51000. El correo es de uso interno del NotificacionPort (no se expone por HTTP).
-- Columnas: rolDestinatario ('ESTUDIANTE' | 'DOCENTE'), idUsuario, nombreCompleto, correo, idSesion, idGrupo, nombreAsignatura,
-- nombreGrupo ('G01 de <asignatura>'), fecha (DATE local), fechaHoraInicio, fechaHoraFin (UTC), motivoCancelacion (con el prefijo).
-- Orden: rol, nombre, inicio.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, cancelaciones por uv_sesion_cancelacion/uv_sesion (antes, las tablas) y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_receso_academico]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idReceso          UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRecesoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idReceso, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)     = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idInstitucion         UNIQUEIDENTIFIER;
    DECLARE @fechaReceso           DATE;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @p1 NVARCHAR(500) = CONVERT(NVARCHAR(36), @idRecesoDefecto);
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 3: Institucion del administrador ejecutor
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
                @idUsuario = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacionDefecto,
                @idInstitucion = @idInstitucion OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Receso activo de esa institucion (REC_009)
        IF @estadoResultado = 1
        BEGIN
            SELECT @fechaReceso = r.fecha
            FROM dbo.uv_periodo_receso_academico r
            WHERE r.id = @idRecesoDefecto AND r.idInstitucion = @idInstitucion;

            IF @fechaReceso IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REC_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Rechazo: THROW 51000 con el mensaje tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 6: Estudiantes activos y docentes de las sesiones canceladas por el receso
        WITH cancelaciones AS (
            SELECT  sc.idSesion AS idSesion, s.idGrupo AS idGrupo, s.fechaHoraInicio, s.fechaHoraFin, sc.motivo
            FROM    dbo.uv_sesion_cancelacion sc
            INNER JOIN dbo.uv_sesion s ON s.id = sc.idSesion
            WHERE   sc.idRecesoAcademico = @idRecesoDefecto
        )
        SELECT  rolDestinatario  = CAST(x.rolDestinatario AS VARCHAR(12)),
                idUsuario        = x.idUsuario,
                nombreCompleto   = CAST(x.nombreCompleto AS NVARCHAR(400)),
                correo           = x.correo,
                idSesion         = x.idSesion,
                idGrupo          = x.idGrupo,
                nombreAsignatura = x.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(x.codigoGrupo, '00'), N' de ', x.nombreAsignatura) AS NVARCHAR(300)),
                fecha            = @fechaReceso,
                fechaHoraInicio  = x.fechaHoraInicio,
                fechaHoraFin     = x.fechaHoraFin,
                motivoCancelacion = x.motivo
        FROM (
            SELECT  rolDestinatario = 'ESTUDIANTE', ei.idUsuario, ei.nombreCompleto, u.correo, c.idSesion, c.idGrupo,
                    g.nombreAsignatura, g.codigo AS codigoGrupo, c.fechaHoraInicio, c.fechaHoraFin, c.motivo
            FROM    cancelaciones c
            INNER JOIN dbo.uv_grupo g ON g.id = c.idGrupo
            INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = c.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
            INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
            INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
            UNION ALL
            SELECT  'DOCENTE', di.idUsuario, di.nombreCompleto, u.correo, c.idSesion, c.idGrupo,
                    g.nombreAsignatura, g.codigo, c.fechaHoraInicio, c.fechaHoraFin, c.motivo
            FROM    cancelaciones c
            INNER JOIN dbo.uv_grupo g ON g.id = c.idGrupo
            INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
            INNER JOIN dbo.uv_usuario u ON u.id = di.idUsuario
        ) x
        ORDER BY x.rolDestinatario, x.nombreCompleto, x.fechaHoraInicio, x.idSesion;
    END TRY
    BEGIN CATCH
        -- PASO 7: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
