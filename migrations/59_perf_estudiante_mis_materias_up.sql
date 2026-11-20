-- ============================================================================
-- MIGRACION UP 59: PERF-EST-MM rendimiento de "Mis materias" del estudiante (docs/work-items/PERF-estudiante-mis-materias/PLAN.md)
--   1. Crea ufn_calcular_fecha_limite_justificacion_conjunto: version en linea (funcion de tabla) de
--      ufn_calcular_fecha_limite_justificacion, con la misma regla y el mismo resultado. La escalar no cambia.
--   2. Recompila uv_sesion_estudiante_reclamo y uv_asistencia_toma_estudiante para usarla: el limite y el codigo
--      RECLAMO/ESTADO_RETIRADO se leen como conjunto y no por fila. Mismas columnas, mismos tipos, mismos valores.
--   3. Recompila usp_consultar_sesiones_materia_estudiante: filtra y pagina primero y calcula el limite solo para la pagina.
--      Mismo resultset (columnas, orden y total). Los permisos se conservan (CREATE OR ALTER).
--   4. Indices: IX_EstudianteGrupo_Estudiante, IX_EstudianteGrupo_Grupo, IX_Grupo_Asignatura, IX_Asistencia_Sesion.
-- Sin cambios de columnas ni de datos. Idempotente. Down: 59_perf_estudiante_mis_materias_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 59 UP: PERF-EST-MM rendimiento de Mis materias del estudiante';
GO
-- ---- schema/functions/ufn_calcular_fecha_limite_justificacion_conjunto.sql

-- ============================================================================
-- ufn_calcular_fecha_limite_justificacion_conjunto (PERF-EST-MM, docs/work-items/PERF-estudiante-mis-materias/PLAN.md)
--
-- Version en linea (funcion de tabla de una sola sentencia) de ufn_calcular_fecha_limite_justificacion: misma regla y mismo
-- resultado (CULM-001 D.1, HU026B; CONTRACT §0 [SUPUESTO-D-01], §2.2). Devuelve una fila con fechaLimiteUtc:
--   limite EXCLUSIVO (UTC) = medianoche local (TIEMPO/ZONA_HORARIA_SQLSERVER) del dia
--   fecha local de fin de la sesion + N + 1,   N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION.
-- NULL si @fechaHoraFinSesionUtc es NULL, si N falta, es vacio, no es entero o es negativo, si la zona falta, es vacia o no
-- existe en sys.time_zone_info, o si el limite se sale del rango de DATE.
--
-- Por que existe: la funcion escalar tiene varias sentencias, lee dos parametros y sys.time_zone_info en cada llamada y no
-- se puede expandir en linea; usada por fila en vistas (uv_sesion_estudiante_reclamo, uv_asistencia_toma_estudiante)
-- obliga a planes en serie y a una evaluacion fila por fila. Esta version se expande dentro de la consulta: los dos
-- parametros y la zona se leen como un conjunto constante y solo la aritmetica de fechas se hace por fila.
-- Los parametros se leen con la misma semantica de ufn_obtener_parametro (valor, si no valorDefecto, si no '';
-- uv_parametro solo trae los activos) seguida del TRIM de ufn_obtener_parametro_texto.
-- La zona invalida se reemplaza por 'UTC' antes de AT TIME ZONE (que fallaria con un nombre inexistente); el resultado de
-- esa rama se descarta porque zonaValida = 0 devuelve NULL.
-- Sin escrituras. Uso: CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(s.fechaHoraFin) lim.
-- La funcion escalar se conserva sin cambios para los llamadores de un solo valor; test_perf_estudiante_mis_materias.sql
-- comprueba que las dos den el mismo resultado.
-- ============================================================================

-- Una funcion en linea exige que uv_parametro exista al crearse; las funciones se despliegan antes que las vistas
-- (mismo resguardo que ufn_obtener_parametro). La vista real la reemplaza al desplegar schema/views.
IF OBJECT_ID('dbo.uv_parametro', 'V') IS NULL
BEGIN
    EXEC('CREATE VIEW dbo.uv_parametro AS SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS id, CAST('' '' AS VARCHAR(100)) AS grupo, CAST('' '' AS VARCHAR(100)) AS clave, CAST('' '' AS NVARCHAR(MAX)) AS valor, CAST(''STRING'' AS VARCHAR(20)) AS tipoDato, CAST('' '' AS NVARCHAR(MAX)) AS valorDefecto, CAST(1 AS BIT) AS estaActivo, GETDATE() AS fechaCreacion, GETDATE() AS fechaModificacion');
END
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_fecha_limite_justificacion_conjunto] (
    @fechaHoraFinSesionUtc DATETIME2(7)
)
RETURNS TABLE
AS
RETURN
SELECT  fechaLimiteUtc = CAST(CASE
                WHEN @fechaHoraFinSesionUtc IS NULL OR cfg.dias IS NULL OR cfg.zonaValida = 0 THEN NULL
                WHEN cfg.dias + 1 > DATEDIFF(DAY, loc.fechaLocalFin, CAST('9999-12-30' AS DATE)) THEN NULL
                ELSE (CAST(DATEADD(DAY, cfg.dias + 1, loc.fechaLocalFin) AS DATETIME2(7)) AT TIME ZONE cfg.zona) AT TIME ZONE 'UTC'
            END AS DATETIME2(7))
FROM (
        SELECT  dias = CASE WHEN txt.textoDias = N'' OR TRY_CAST(txt.textoDias AS INT) < 0 THEN NULL
                            ELSE TRY_CAST(txt.textoDias AS INT) END,
                zonaValida = CAST(IIF(txt.textoZona <> N''
                                      AND EXISTS (SELECT 1 FROM sys.time_zone_info tz WHERE tz.name = txt.textoZona), 1, 0) AS BIT),
                zona = CAST(IIF(txt.textoZona <> N''
                                AND EXISTS (SELECT 1 FROM sys.time_zone_info tz WHERE tz.name = txt.textoZona),
                                txt.textoZona, N'UTC') AS NVARCHAR(128))
        FROM (
                SELECT  textoDias = TRIM(ISNULL((SELECT TOP (1) ISNULL(p.valor, ISNULL(p.valorDefecto, N''))
                                                FROM dbo.uv_parametro p
                                                WHERE p.grupo = 'ASISTENCIA' AND p.clave = 'DIAS_LIMITE_JUSTIFICACION'), N'')),
                        textoZona = TRIM(ISNULL((SELECT TOP (1) ISNULL(p.valor, ISNULL(p.valorDefecto, N''))
                                                FROM dbo.uv_parametro p
                                                WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER'), N''))
             ) txt
     ) cfg
CROSS APPLY (SELECT fechaLocalFin = CAST((@fechaHoraFinSesionUtc AT TIME ZONE 'UTC') AT TIME ZONE cfg.zona AS DATE)) loc;
GO
-- ---- schema/views/uv_sesion_estudiante_reclamo.sql

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion_conjunto(fechaHoraFin)  (limite exclusivo; NULL si falta
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
-- PERF-EST-MM: version en linea de ufn_calcular_fecha_limite_justificacion (mismo resultado): los parametros y la zona se leen
-- una vez por consulta y no por fila; la escalar obligaba a un plan en serie evaluado fila por fila.
CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(s.fechaHoraFin) lim
WHERE   esol.id IS NULL OR esol.esAprobada = 1;
GO
-- ---- schema/views/uv_asistencia_toma_estudiante.sql

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
                                AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT),
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
-- PERF-EST-MM: el limite (ufn_calcular_fecha_limite_justificacion_conjunto, misma regla que la escalar) y el codigo RECLAMO/ESTADO_RETIRADO
-- (misma lectura que ufn_obtener_parametro: valor, si no valorDefecto, si no '') se resuelven como conjunto, no por fila.
CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(pc.fechaHoraFinSesion) lim
CROSS JOIN (
        SELECT  codigoRetirado = CAST(ISNULL((SELECT TOP (1) ISNULL(p.valor, ISNULL(p.valorDefecto, N''))
                                              FROM dbo.uv_parametro p
                                              WHERE p.grupo = 'RECLAMO' AND p.clave = 'ESTADO_RETIRADO'), N'') AS NVARCHAR(5))
) ret
OUTER APPLY (
        SELECT  TOP 1 idSolicitud = sra.id, codigoEstado = e.codigo, codigoResultado = rcr.codigo
        FROM    dbo.SolicitudRevisionAsistencia sra
        INNER JOIN dbo.Estado e ON e.id = sra.estado
        LEFT JOIN dbo.RazonCausa rcr ON rcr.id = sra.razonCausaResolucion
        WHERE   sra.asistencia = a.id AND sra.toma = pc.idToma
          AND   e.codigo <> ret.codigoRetirado
        ORDER BY sra.fecha DESC, sra.id DESC
) sol;
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_materia_estudiante.sql

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
    -- PERF-EST-MM: primero se filtran las matriculas inscritas del ejecutor en la materia (y el grupo opcional), se cuentan y se
    -- toma la pagina con las columnas baratas; la fecha limite (ufn_calcular_fecha_limite_justificacion_conjunto, la misma regla
    -- de la vista) se calcula solo para las filas de la pagina. Mismas columnas, mismo orden, mismo total y mismo plazo que
    -- cuando se leian fechaLimiteJustificacionUtc / plazoJustificacionVigente de uv_sesion_estudiante_reclamo.
    SELECT
        id                          = pag.idSesion,
        nombre                      = pag.nombre,
        numero                      = pag.numero,
        codigo                      = pag.codigo,
        numeroSemana                = pag.numeroSemana,
        idGrupo                     = pag.idGrupo,
        codigoGrupo                 = pag.codigoGrupo,
        nombreGrupo                 = pag.nombreGrupo,
        fechaHoraInicio             = pag.fechaHoraInicio,
        fechaHoraFin                = pag.fechaHoraFin,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente   = CAST(IIF(pag.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                               AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT),
        totalRegistros              = pag.totalRegistros
    FROM (
        SELECT  r.idSesion, r.nombre, r.numero, r.codigo, r.numeroSemana, r.idGrupo, r.codigoGrupo, r.nombreGrupo,
                r.fechaHoraInicio, r.fechaHoraFin, r.estaCancelada,
                totalRegistros = COUNT(1) OVER()
        FROM dbo.uv_sesion_estudiante_reclamo r
        INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
        WHERE e.usuario = @idUsuarioDefecto
          AND r.idAsignatura = @idMateria
          AND r.codigoEstadoEstudiante = @codigoInscrita
          AND (@idGrupo IS NULL OR r.idGrupo = @idGrupo)
        ORDER BY r.fechaHoraInicio ASC, r.numero ASC, r.idSesion ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY
    ) pag
    CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(pag.fechaHoraFin) lim
    ORDER BY pag.fechaHoraInicio ASC, pag.numero ASC, pag.idSesion ASC;
END;
GO
-- ---- schema/tables/EstudianteGrupo.sql (indices PERF-EST-MM)
-- PERF-EST-MM (docs/work-items/PERF-estudiante-mis-materias/PLAN.md): las vistas del estudiante filtran las matriculas por
-- estudiante (uv_estudiante_grupo, uv_materia_estudiante, sesiones de la materia) y unen por grupo (uv_sesion_estudiante_reclamo,
-- resumenes por grupo). Sin estos indices cada consulta recorre la tabla completa.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_Estudiante')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_Estudiante ON dbo.EstudianteGrupo (estudiante) INCLUDE (grupo, estado);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_Grupo')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_Grupo ON dbo.EstudianteGrupo (grupo) INCLUDE (estudiante, estado);
GO
-- ---- schema/tables/Grupo.sql (indices PERF-EST-MM)
-- PERF-EST-MM: las consultas del estudiante y del coordinador filtran los grupos por asignatura (g.asignatura = @idMateria).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_Asignatura')
    CREATE NONCLUSTERED INDEX IX_Grupo_Asignatura ON dbo.Grupo (asignatura) INCLUDE (periodoAcademico, docente);
GO
-- ---- schema/tables/Asistencia.sql (indices PERF-EST-MM)
-- PERF-EST-MM: uv_toma_punto_control, uv_asistencia_tramo y uv_asistencia_toma_estudiante unen las cabeceras por sesion;
-- UX_Asistencia_EstudianteGrupo_Sesion empieza por estudianteGrupo y no sirve para buscar por sesion.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Asistencia') AND name = 'IX_Asistencia_Sesion')
    CREATE NONCLUSTERED INDEX IX_Asistencia_Sesion ON dbo.Asistencia (sesion) INCLUDE (estudianteGrupo);
GO
PRINT 'MIGRACION 59 UP: completada';
GO
