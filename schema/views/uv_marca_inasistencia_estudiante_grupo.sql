USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): marca de inasistencia por matricula (alertas vigentes y estado de la revision) para la planilla
-- del docente. Una fila por matricula con alerta o revision; no lee uv_grupo_programa ni uv_resumen_*.
CREATE OR ALTER VIEW [dbo].[uv_marca_inasistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = k.estudianteGrupo,
        tieneAdvertenciaVigente = CAST(ISNULL(al.tieneAdvertencia, 0) AS BIT),
        fechaAdvertenciaUtc = al.fechaAdvertencia,
        tienePerdidaVigente = CAST(ISNULL(al.tienePerdida, 0) AS BIT),
        fechaPerdidaUtc = al.fechaPerdida,
        idRevisionCancelacion = r.id,
        codigoEstadoRevision = es.codigo,
        nombreEstadoRevision = es.nombre,
        requiereAccionDocente = es.requiereAccionDocente,
        requiereAccionResolutor = es.requiereAccionResolutor,
        conservaMatricula = es.conservaMatricula,
        esFinalRevision = es.esFinal,
        codigoPerfilResolutorActual = r.codigoPerfilResolutorActual
FROM    (SELECT estudianteGrupo FROM dbo.AlertaInasistencia UNION SELECT estudianteGrupo FROM dbo.RevisionCancelacion) k
LEFT JOIN dbo.RevisionCancelacion r ON r.estudianteGrupo = k.estudianteGrupo
LEFT JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
OUTER APPLY (
    SELECT  tieneAdvertencia = MAX(IIF(t.creaRevisionCancelacion = 0 AND s.estaVigente = 1, 1, 0)),
            fechaAdvertencia = MAX(IIF(t.creaRevisionCancelacion = 0 AND s.estaVigente = 1, a.fechaCruceUtc, NULL)),
            tienePerdida = MAX(IIF(t.creaRevisionCancelacion = 1 AND s.estaVigente = 1, 1, 0)),
            fechaPerdida = MAX(IIF(t.creaRevisionCancelacion = 1 AND s.estaVigente = 1, a.fechaCruceUtc, NULL))
    FROM    dbo.AlertaInasistencia a
    INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = a.tipo
    INNER JOIN dbo.EstadoAlertaInasistencia s ON s.id = a.estado
    WHERE   a.estudianteGrupo = k.estudianteGrupo
) al;
GO
