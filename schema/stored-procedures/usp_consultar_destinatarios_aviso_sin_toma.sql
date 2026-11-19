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
-- Destinatarios: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo; en un grupo compartido, uno por
-- programa) con usuario activo y correo; una persona que coordina dos de esos programas sale una sola vez.
-- Una sesion inexistente, cancelada, o con alguna toma devuelve 0 filas (el aviso ya no aplica).
-- Los correos son de uso interno del NotificacionPort; el backend no los expone ni los registra.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_aviso_sin_toma]
(
    @idSesion      UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

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
        FROM dbo.ufn_programas_grupo(se.idGrupo) pg
        INNER JOIN dbo.Programa p                   ON p.id = pg.idPrograma
        INNER JOIN dbo.uv_coordinador_identidad ci  ON ci.id = p.coordinador
                                                   AND ci.estaActivoRolCoordinador = 1 AND ci.estaActivoUsuario = 1
        WHERE ci.correo IS NOT NULL AND LEN(TRIM(ci.correo)) > 0
    ) co
    WHERE se.idSesion = @idSesionDefecto
      AND se.estaCancelada = 0
      AND se.totalTomas = 0
    ORDER BY co.nombreCompleto ASC, co.idUsuario ASC;
END;
GO
