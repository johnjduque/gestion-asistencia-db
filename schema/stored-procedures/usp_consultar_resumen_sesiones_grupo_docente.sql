USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_sesiones_grupo_docente (CIERRE-W3M, puntos 2 y 3; DEC-066)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- GRU_*, SEC_002). RBAC DOCENTE titular del grupo (el ambito se valida antes de leer filas).
-- Resumen del grupo para el docente, resuelto en la base con la hora actual (SYSUTCDATETIME(): las sesiones se guardan en UTC,
-- igual que uv_cumplimiento_sesion_grupo.estaVencida) y los umbrales de catalogo: una fila por sesion del grupo (orden numero)
-- con su estado temporal y sus conteos sobre las matriculas ACTIVAS, mas columnas del grupo repetidas en cada fila. Un grupo sin
-- sesiones devuelve UNA fila con idSesion NULL (conserva las columnas del grupo). Sin paginacion: las sesiones de un grupo son
-- acotadas (la lista de sesiones del grupo tampoco se pagina).
--   estadoSesion: CANCELADA (SesionCancelacion: incluye festivos y solicitudes rechazadas); si no, PROGRAMADA cuando el horario
--   no esta confirmado (procedenciaTemporal NULL) o aun no inicia, EN_CURSO si inicio <= ahora < fin, EJECUTADA si fin <= ahora.
--   presentes / parciales / justificadas / ausentes: matriculas activas con codigoEstadoSesionEstudiante PRESENTE / PARCIAL /
--   JUSTIFICADA / AUSENTE (uv_asistencia_sesion_horas); sinRegistro = totalEstudiantes menos esas cuatro (0 si esta cancelada).
--   Grupo: sesionesProgramadas = todas las sesiones (incluye ejecutadas y canceladas), sesionesEjecutadas, sesionesCanceladas,
--   sesionesEnCurso, idSesionEnCurso, idSesionProxima (la PROGRAMADA confirmada con inicio > ahora mas cercana),
--   estudiantesActivos, estudiantesEnRiesgo (codigoPermanencia RIESGO o PERDIDA), promedioAsistencia (promedio de
--   porcentajeAsistenciaHoras de las matriculas activas; NULL si no hay horas dictadas), umbralAdvertencia, umbralPerdida.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_sesiones_grupo_docente]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();

    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacionDefecto, @idGrupo = @idGrupo,
        @validarPaginacion = 0, @numeroPagina = NULL, @tamanoPagina = NULL,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    DECLARE @sesiones TABLE (
        idSesion UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, numero INT NULL, nombre NVARCHAR(200) NULL,
        fechaHoraInicio DATETIME2(7) NULL, fechaHoraFin DATETIME2(7) NULL, procedenciaTemporal NVARCHAR(24) NULL,
        estadoSesion NVARCHAR(20) NOT NULL, estadoSolicitud NVARCHAR(50) NULL, pendienteAprobacion BIT NULL,
        presentes INT NOT NULL, parciales INT NOT NULL, justificadas INT NOT NULL, ausentes INT NOT NULL);

    INSERT INTO @sesiones
    SELECT
        s.idSesion, s.numero, s.nombre, s.fechaHoraInicio, s.fechaHoraFin, s.procedenciaTemporal,
        CASE WHEN s.estaCancelada = 1 THEN N'CANCELADA'
             WHEN s.procedenciaTemporal IS NULL THEN N'PROGRAMADA'
             WHEN s.fechaHoraFin <= @ahora THEN N'EJECUTADA'
             WHEN s.fechaHoraInicio <= @ahora THEN N'EN_CURSO'
             ELSE N'PROGRAMADA' END,
        s.estadoSolicitud, s.pendienteAprobacion,
        ISNULL(c.presentes, 0), ISNULL(c.parciales, 0), ISNULL(c.justificadas, 0), ISNULL(c.ausentes, 0)
    FROM dbo.uv_sesion_estado s
    OUTER APPLY (
        SELECT presentes    = SUM(IIF(h.codigoEstadoSesionEstudiante = N'PRESENTE', 1, 0)),
               parciales    = SUM(IIF(h.codigoEstadoSesionEstudiante = N'PARCIAL', 1, 0)),
               justificadas = SUM(IIF(h.codigoEstadoSesionEstudiante = N'JUSTIFICADA', 1, 0)),
               ausentes     = SUM(IIF(h.codigoEstadoSesionEstudiante = N'AUSENTE', 1, 0))
        FROM dbo.uv_asistencia_sesion_horas h
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = h.idEstudianteGrupo AND eg.codigoEstadoEstudiante = @codigoInscrita
        WHERE h.idGrupo = @idGrupoDefecto AND h.idSesion = s.idSesion
    ) c
    WHERE s.idGrupo = @idGrupoDefecto;

    SELECT
        idSesion            = s.idSesion,
        numero              = s.numero,
        nombre              = s.nombre,
        fechaHoraInicio     = s.fechaHoraInicio,
        fechaHoraFin        = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estadoSesion        = s.estadoSesion,
        estadoSolicitud     = s.estadoSolicitud,
        pendienteAprobacion = s.pendienteAprobacion,
        totalEstudiantes    = ga.estudiantesActivos,
        presentes           = s.presentes,
        parciales           = s.parciales,
        justificadas        = s.justificadas,
        ausentes            = s.ausentes,
        sinRegistro         = CASE WHEN s.estadoSesion = N'CANCELADA' THEN 0
                                   ELSE IIF(ga.estudiantesActivos - s.presentes - s.parciales - s.justificadas - s.ausentes < 0, 0,
                                            ga.estudiantesActivos - s.presentes - s.parciales - s.justificadas - s.ausentes) END,
        sesionesProgramadas = (SELECT COUNT(1) FROM @sesiones),
        sesionesEjecutadas  = (SELECT COUNT(1) FROM @sesiones x WHERE x.estadoSesion = N'EJECUTADA'),
        sesionesCanceladas  = (SELECT COUNT(1) FROM @sesiones x WHERE x.estadoSesion = N'CANCELADA'),
        sesionesEnCurso     = (SELECT COUNT(1) FROM @sesiones x WHERE x.estadoSesion = N'EN_CURSO'),
        idSesionEnCurso     = (SELECT TOP 1 x.idSesion FROM @sesiones x WHERE x.estadoSesion = N'EN_CURSO'
                               ORDER BY x.fechaHoraInicio ASC, x.numero ASC),
        idSesionProxima     = (SELECT TOP 1 x.idSesion FROM @sesiones x
                               WHERE x.estadoSesion = N'PROGRAMADA' AND x.procedenciaTemporal IS NOT NULL AND x.fechaHoraInicio > @ahora
                               ORDER BY x.fechaHoraInicio ASC, x.numero ASC),
        estudiantesActivos  = ga.estudiantesActivos,
        estudiantesEnRiesgo = ga.estudiantesEnRiesgo,
        promedioAsistencia  = ga.promedioAsistencia,
        umbralAdvertencia   = ga.umbralAdvertencia,
        umbralPerdida       = ga.umbralPerdida
    FROM (
        SELECT estudiantesActivos  = COUNT(r.idEstudianteGrupo),
               estudiantesEnRiesgo = ISNULL(SUM(IIF(r.codigoPermanencia IN (N'RIESGO', N'PERDIDA'), 1, 0)), 0),
               promedioAsistencia  = CAST(IIF(ISNULL(SUM(r.horasDictadas), 0) = 0, NULL, AVG(r.porcentajeAsistenciaHoras)) AS DECIMAL(5,2)),
               umbralAdvertencia   = MAX(r.umbralAdvertencia),
               umbralPerdida       = MAX(r.umbralPerdida)
        FROM dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE r.idGrupo = @idGrupoDefecto AND r.codigoEstadoEstudiante = @codigoInscrita
    ) ga
    LEFT JOIN @sesiones s ON 1 = 1
    ORDER BY s.numero ASC, s.idSesion ASC;
END;
GO
