-- ============================================================================
-- MIGRACION DOWN 59: retira PERF-EST-MM
--   Restaura el texto de develop (antes de la 59) de uv_sesion_estudiante_reclamo, uv_asistencia_toma_estudiante y
--   usp_consultar_sesiones_materia_estudiante (vuelven a llamar la escalar ufn_calcular_fecha_limite_justificacion por fila),
--   elimina ufn_calcular_fecha_limite_justificacion_conjunto y los cuatro indices. Los permisos se conservan. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 59 DOWN: retira PERF-EST-MM';
GO
-- ---- schema/views/uv_sesion_estudiante_reclamo.sql (texto de develop antes de la 59)

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion(fechaHoraFin)  (limite exclusivo; NULL si falta
--                                 ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER)
--   plazoJustificacionVigente   = 1 solo si la sesion NO esta cancelada y SYSUTCDATETIME() < limite
-- idAsignatura, codigo, numeroSemana, codigoGrupo, nombreGrupo y codigoEstadoEstudiante completan las columnas que hoy
-- entrega la consulta de sesiones de la materia y permiten al SP filtrar la matricula inscrita.
-- CULM-001 / DEC-065 (2): el estudiante solo ve las sesiones sin solicitud (generadas y manuales anteriores) y las extraordinarias
-- aprobadas por el coordinador; las pendientes y las rechazadas (nunca se le anunciaron) no se listan.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estudiante_reclamo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idAsignatura = g.idAsignatura,
        numero = s.numero,
        nombre = s.nombre,
        codigo = s.codigo,
        numeroSemana = s.numeroSemana,
        codigoGrupo = s.codigoGrupo,
        nombreGrupo = s.nombreGrupo,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaCancelada = se.estaCancelada,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente = CAST(IIF(se.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                             AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_sesion_estado se
ON      se.idSesion = s.id
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.idGrupo
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
LEFT JOIN dbo.SesionSolicitud ssol
ON      ssol.sesion = s.id
LEFT JOIN dbo.EstadoSolicitudSesion esol
ON      esol.id = ssol.idEstado
CROSS APPLY (SELECT fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)) lim
WHERE   esol.id IS NULL OR esol.esAprobada = 1;
GO
-- ---- schema/views/uv_asistencia_toma_estudiante.sql (texto de develop antes de la 59)

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B, reclamo por toma): una fila por (cabecera
-- Asistencia, toma de su sesion), incluidas las tomas sin detalle del estudiante. La consume el backend (sesiones de la materia
-- del estudiante): el estado del estudiante en cada toma, los minutos de los tramos vecinos y si la toma se puede reclamar.
--   codigoRazonCausa             marca del estudiante en la toma (NULL = sin registro).
--   codigoEstadoTomaEstudiante   PRESENTE (AN), AUSENTE (SJC), JUSTIFICADA (EX) o SIN_REGISTRO (sin marca u otra razon).
--   idSolicitudRevision / codigoEstadoSolicitud / codigoResultadoAprobacion: la solicitud NO retirada (RECLAMO/ESTADO_RETIRADO)
--   mas reciente de esa toma (NULL si no hay); el resultado de la aprobacion es AN o EX.
--   esReclamable = marca SJC, sin solicitud no retirada de la toma, sesion no cancelada y plazo HU026B vigente
--   (ufn_calcular_fecha_limite_justificacion sobre el fin de la sesion, el mismo criterio de uv_sesion_estudiante_reclamo).
-- Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_toma_estudiante]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idToma = pc.idToma,
        numeroToma = pc.numero,
        ordenPuntoControl = pc.ordenPuntoControl,
        fechaPuntoControlUtc = pc.fechaPuntoControlUtc,
        codigoRazonCausa = rc.codigo,
        minutosTramoAnterior = pc.minutosTramoAnterior,
        minutosTramoSiguiente = pc.minutosTramoSiguiente,
        idSolicitudRevision = sol.idSolicitud,
        codigoEstadoSolicitud = sol.codigoEstado,
        codigoResultadoAprobacion = sol.codigoResultado,
        esReclamable = CAST(IIF(rc.codigo = N'SJC'
                                AND sol.idSolicitud IS NULL
                                AND pc.estaSesionCancelada = 0
                                AND SYSUTCDATETIME() < dbo.ufn_calcular_fecha_limite_justificacion(pc.fechaHoraFinSesion), 1, 0) AS BIT),
        idEstudiante = eg.estudiante,
        codigoEstadoTomaEstudiante = CAST(CASE rc.codigo WHEN N'AN' THEN N'PRESENTE'
                                                         WHEN N'SJC' THEN N'AUSENTE'
                                                         WHEN N'EX' THEN N'JUSTIFICADA'
                                                         ELSE N'SIN_REGISTRO' END AS NVARCHAR(20))
FROM    dbo.Asistencia a
INNER JOIN dbo.EstudianteGrupo eg
ON      eg.id = a.estudianteGrupo
INNER JOIN dbo.uv_toma_punto_control pc
ON      pc.idSesion = a.sesion
LEFT JOIN dbo.DetalleAsistencia d
ON      d.asistencia = a.id AND d.toma = pc.idToma
LEFT JOIN dbo.RazonCausa rc
ON      rc.id = d.razonCausa
OUTER APPLY (
        SELECT  TOP 1 idSolicitud = sra.id, codigoEstado = e.codigo, codigoResultado = rcr.codigo
        FROM    dbo.SolicitudRevisionAsistencia sra
        INNER JOIN dbo.Estado e ON e.id = sra.estado
        LEFT JOIN dbo.RazonCausa rcr ON rcr.id = sra.razonCausaResolucion
        WHERE   sra.asistencia = a.id AND sra.toma = pc.idToma
          AND   e.codigo <> CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5))
        ORDER BY sra.fecha DESC, sra.id DESC
) sol;
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_materia_estudiante.sql (texto de develop antes de la 59)

-- ============================================================================
-- usp_consultar_sesiones_materia_estudiante (CULM-001 D.1, HU026B; CONTRACT §2.2, DEC-044 (2))
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001). Sesiones de GET /api/v1/estudiante/materias/{materiaId}/sesiones. RBAC ESTUDIANTE; el ambito esta dentro del SP:
-- solo las matriculas del ejecutor con el estado de MATRICULA/ESTADO_INSCRITA en los grupos de la asignatura @idMateria
-- (los grupos I, CI, CVP y F no devuelven filas: cambio intencional de DEC-022 §3; una materia ajena devuelve 0 filas).
-- Columnas: id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin
-- (las de la consulta que sustituye), fechaLimiteJustificacionUtc, plazoJustificacionVigente y totalRegistros
-- (COUNT(1) OVER()). Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO. Solo lectura.
-- CIERRE-W2B: orden determinista y cronologico: fechaHoraInicio ASC, numero ASC, id ASC (el mismo criterio que antes aplicaba la
-- pantalla en el cliente, con el identificador como desempate estable: dos paginas nunca repiten ni saltan filas). Parametro
-- opcional @idGrupo (NULL = todos los grupos de la asignatura en los que el estudiante esta inscrito): un grupo en el que el
-- ejecutor no esta inscrito devuelve 0 filas, igual que una materia ajena.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_materia_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idMateria         UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 100,
    @idGrupo           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idMateria IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idMateria',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        id                          = r.idSesion,
        nombre                      = r.nombre,
        numero                      = r.numero,
        codigo                      = r.codigo,
        numeroSemana                = r.numeroSemana,
        idGrupo                     = r.idGrupo,
        codigoGrupo                 = r.codigoGrupo,
        nombreGrupo                 = r.nombreGrupo,
        fechaHoraInicio             = r.fechaHoraInicio,
        fechaHoraFin                = r.fechaHoraFin,
        fechaLimiteJustificacionUtc = r.fechaLimiteJustificacionUtc,
        plazoJustificacionVigente   = r.plazoJustificacionVigente,
        totalRegistros              = COUNT(1) OVER()
    FROM dbo.uv_sesion_estudiante_reclamo r
    INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
    WHERE e.usuario = @idUsuarioDefecto
      AND r.idAsignatura = @idMateria
      AND r.codigoEstadoEstudiante = @codigoInscrita
      AND (@idGrupo IS NULL OR r.idGrupo = @idGrupo)
    ORDER BY r.fechaHoraInicio ASC, r.numero ASC, r.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
-- ---- funcion e indices de la 59
DROP FUNCTION IF EXISTS [dbo].[ufn_calcular_fecha_limite_justificacion_conjunto];
GO
DROP INDEX IF EXISTS IX_EstudianteGrupo_Estudiante ON dbo.EstudianteGrupo;
GO
DROP INDEX IF EXISTS IX_EstudianteGrupo_Grupo ON dbo.EstudianteGrupo;
GO
DROP INDEX IF EXISTS IX_Grupo_Asignatura ON dbo.Grupo;
GO
DROP INDEX IF EXISTS IX_Asistencia_Sesion ON dbo.Asistencia;
GO
PRINT 'MIGRACION 59 DOWN: completada';
GO
