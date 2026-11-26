USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_aviso_sin_toma (NOTOMA-001)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario). Resultset: una fila por coordinador destinatario del aviso
-- "el docente no tomo asistencia en la sesion": idSesion, idGrupo, idAsignatura, nombreAsignatura, nombreGrupo, nombreDocente,
-- fechaHoraInicioUtc, fechaHoraFinUtc, idUsuarioCoordinador, nombreCoordinador, correoCoordinador.
-- Destinatarios (DEC-077): el coordinador activo del programa responsable del grupo (ufn_programas_grupo_responsable; en un grupo
-- compartido, uno solo) con usuario activo y correo.
-- Una sesion inexistente, cancelada, o con alguna toma devuelve 0 filas (el aviso ya no aplica).
-- Los correos son de uso interno del NotificacionPort; el backend no los expone ni los registra.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_aviso_sin_toma]
(
    @idSesion      UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Coordinadores activos con correo del programa responsable de una sesion sin tomas
        SELECT
            idSesion             = se.idSesion,
            idGrupo              = se.idGrupo,
            idAsignatura         = g.idAsignatura,
            nombreAsignatura     = g.nombreAsignatura,
            nombreGrupo          = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
            nombreDocente        = CAST(di.nombreCompleto AS NVARCHAR(400)),
            fechaHoraInicioUtc   = se.fechaHoraInicio,
            fechaHoraFinUtc      = se.fechaHoraFin,
            idUsuarioCoordinador = co.idUsuario,
            nombreCoordinador    = CAST(co.nombreCompleto AS NVARCHAR(400)),
            correoCoordinador    = co.correo
        FROM dbo.uv_sesion_estado se
        INNER JOIN dbo.uv_grupo g              ON g.id = se.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        CROSS APPLY (
            SELECT DISTINCT ci.idUsuario, ci.nombreCompleto, ci.correo
            FROM dbo.ufn_programas_grupo_responsable(se.idGrupo) pg
            INNER JOIN dbo.uv_programa p                ON p.id = pg.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad ci  ON ci.id = p.idCoordinador
                                                       AND ci.estaActivoRolCoordinador = 1 AND ci.estaActivoUsuario = 1
            WHERE ci.correo IS NOT NULL AND LEN(TRIM(ci.correo)) > 0
        ) co
        WHERE se.idSesion = @idSesionDefecto
          AND se.estaCancelada = 0
          AND se.totalTomas = 0
        ORDER BY co.nombreCompleto ASC, co.idUsuario ASC;
    END TRY
    BEGIN CATCH
        -- PASO 2: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
