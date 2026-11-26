USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_faltas_sesion_aviso (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario). Resultset: una fila por (estudiante con al menos una toma en SJC,
-- toma en SJC) de la sesion: idSesion, idGrupo, idAsignatura, nombreAsignatura, nombreGrupo, fechaHoraInicioUtc, fechaHoraFinUtc,
-- idUsuarioEstudiante, nombreEstudiante, correoEstudiante, numeroToma, fechaPuntoControlUtc, totalTomasSesion, totalTomasEnFalta,
-- minutosFalta (minutos de falta del estudiante en la sesion, por tramos) y fechaLimiteReclamoUtc (ufn_calcular_fecha_limite_justificacion).
-- Solo matriculas activas (MATRICULA/ESTADO_INSCRITA) con usuario activo y correo. Las tomas sin registro o con AN/EX no generan fila.
-- Una sesion cancelada o inexistente devuelve 0 filas. Los correos son de uso interno del NotificacionPort; el backend no los expone ni los registra.
-- ============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera, PASO n, sin ISNULL (un IIF equivalente) y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_faltas_sesion_aviso]
(
    @idSesion      UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Faltas SJC por toma de las matriculas activas con usuario activo y correo (sesion no cancelada)
        SELECT
            idSesion            = se.idSesion,
            idGrupo             = se.idGrupo,
            idAsignatura        = g.idAsignatura,
            nombreAsignatura    = g.nombreAsignatura,
            nombreGrupo         = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
            fechaHoraInicioUtc  = se.fechaHoraInicio,
            fechaHoraFinUtc     = se.fechaHoraFin,
            idUsuarioEstudiante = ei.idUsuario,
            nombreEstudiante    = CAST(ei.nombreCompleto AS NVARCHAR(400)),
            correoEstudiante    = u.correo,
            numeroToma          = tf.numeroToma,
            fechaPuntoControlUtc = tf.fechaPuntoControlUtc,
            totalTomasSesion    = se.totalTomas,
            totalTomasEnFalta   = COUNT(*) OVER (PARTITION BY tf.idEstudianteGrupo),
            minutosFalta        = CAST(IIF(sh.minutosFalta IS NULL, 0, sh.minutosFalta) AS INT),
            fechaLimiteReclamoUtc = dbo.ufn_calcular_fecha_limite_justificacion(se.fechaHoraFin)
        FROM dbo.uv_sesion_estado se
        INNER JOIN dbo.uv_grupo g                    ON g.id = se.idGrupo
        INNER JOIN dbo.uv_asistencia_toma_estudiante tf ON tf.idSesion = se.idSesion AND tf.codigoRazonCausa = N'SJC'
        INNER JOIN dbo.uv_estudiante_grupo eg        ON eg.id = tf.idEstudianteGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei    ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario u                  ON u.id = ei.idUsuario
        LEFT JOIN  dbo.uv_asistencia_sesion_horas sh ON sh.idAsistencia = tf.idAsistencia
        WHERE se.idSesion = @idSesionDefecto
          AND se.estaCancelada = 0
          AND u.correo IS NOT NULL AND LEN(TRIM(u.correo)) > 0
        ORDER BY ei.nombreCompleto ASC, eg.idEstudiante ASC, tf.numeroToma ASC;
    END TRY
    BEGIN CATCH
        -- PASO 2: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
