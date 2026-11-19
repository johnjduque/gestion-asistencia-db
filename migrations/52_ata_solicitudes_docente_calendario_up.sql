-- ============================================================================
-- MIGRACION UP 52: ATA D6 y D7 (solicitudes de sesion del docente y horario semanal con fechas)
--   1. Solicitudes de sesion del docente: usp_consultar_solicitudes_sesion_docente_paginado (mismas columnas y orden que la del
--      coordinador, sobre uv_solicitud_sesion, solo grupos donde es titular).
--   2. Calendario de sesiones: vista uv_sesion_calendario, validacion compartida usp_validar_rango_calendario_interno,
--      usp_consultar_sesiones_calendario_estudiante y usp_consultar_sesiones_calendario_docente, mensaje CAL_001.
--   3. Permisos del rol runtime. Sin cambios de tablas. Idempotente. Down: 52_ata_solicitudes_docente_calendario_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 52 UP: ATA D6/D7 (solicitudes docente y calendario)';
GO
-- ---- schema/views/uv_sesion_calendario.sql
-- ATA D7: una fila por sesion visible del calendario (horario semanal con fechas), sobre uv_sesion_estado (cancelacion, festivo y
-- solicitud ya resueltos alli). Excluye las sesiones cuya solicitud de sesion extraordinaria sigue pendiente o fue rechazada (solo
-- entran las sin solicitud y las aprobadas). esExtraordinaria = sesion manual (uv_sesion_manual). Instantes en UTC; el filtro por
-- fecha local institucional lo aplican los SP usp_consultar_sesiones_calendario_*.
CREATE OR ALTER VIEW [dbo].[uv_sesion_calendario]
AS
SELECT  idSesion = e.idSesion,
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        nombreGrupo = g.nombre,
        idAsignatura = g.idAsignatura,
        codigoAsignatura = a.codigo,
        nombreAsignatura = g.nombreAsignatura,
        idDocente = g.idDocente,
        nombreDocente = di.nombreCompleto,
        fechaHoraInicioUtc = e.fechaHoraInicio,
        fechaHoraFinUtc = e.fechaHoraFin,
        esExtraordinaria = CAST(IIF(m.idSesion IS NULL, 0, 1) AS BIT),
        estaCancelada = e.estaCancelada,
        motivoCancelacion = e.motivoCancelacion,
        esCancelacionAutomatica = e.esCancelacionAutomatica,
        nombreDiaFestivo = e.nombreDiaFestivo
FROM    dbo.uv_sesion_estado e
INNER JOIN dbo.uv_grupo g                    ON g.id = e.idGrupo
INNER JOIN dbo.uv_asignatura a               ON a.id = g.idAsignatura
INNER JOIN dbo.uv_docente_identidad di       ON di.id = g.idDocente
LEFT JOIN  dbo.uv_sesion_manual m            ON m.idSesion = e.idSesion
LEFT JOIN  dbo.uv_estado_solicitud_sesion es ON es.codigo = e.estadoSolicitud
WHERE   e.estadoSolicitud IS NULL OR es.esAprobada = 1;
GO
-- ---- schema/stored-procedures/usp_validar_rango_calendario_interno.sql
-- ============================================================================
-- usp_validar_rango_calendario_interno (ATA D7)
--
-- Validacion compartida de las consultas del calendario de sesiones: correlacion, ejecutor y perfil (via
-- usp_validar_consulta_paginada_interno; aqui se restaura el SESSION_CONTEXT) y rango de fechas locales institucionales:
-- @desde y @hasta presentes, @hasta >= @desde y como maximo @maximoDias dias (CAL_001). Devuelve el ejecutor normalizado y el rango
-- como instantes UTC [@desdeUtc, @hastaUtcExclusivo) segun TIEMPO/ZONA_HORARIA_SQLSERVER. El caller hace THROW 51000 con el
-- mensaje tecnico cuando @estadoResultado = 0. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_rango_calendario_interno]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoPerfilRequerido   NVARCHAR(50),
    @desde                   DATE,
    @hasta                   DATE,
    @idUsuarioValidado       UNIQUEIDENTIFIER OUTPUT,
    @desdeUtc                DATETIME2(7) OUTPUT,
    @hastaUtcExclusivo       DATETIME2(7) OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @maximoDias      INT = 31;
    DECLARE @contextoPrevio  SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @offsetIgnorado  INT;
    DECLARE @zonaTexto       NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
    DECLARE @zona            NVARCHAR(128) = IIF(@zonaTexto IS NULL OR @zonaTexto = N'', N'SA Pacific Standard Time', @zonaTexto);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;

    SELECT @desdeUtc = NULL, @hastaUtcExclusivo = NULL;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = @codigoPerfilRequerido,
        @numeroPagina = 1, @tamanoPagina = 1,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offsetIgnorado OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;

    IF @estadoResultado = 1
       AND (@desde IS NULL OR @hasta IS NULL OR @hasta < @desde OR DATEDIFF(DAY, @desde, @hasta) + 1 > @maximoDias)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(10), @desde, 23), @p2 = CONVERT(NVARCHAR(10), @hasta, 23), @p3 = CONVERT(NVARCHAR(10), @maximoDias);
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'CAL_001', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacion AS NVARCHAR(50)));
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
        SELECT @desdeUtc = CAST((CAST(@desde AS DATETIME2(7)) AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7)),
               @hastaUtcExclusivo = CAST((CAST(DATEADD(DAY, 1, @hasta) AS DATETIME2(7)) AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7));
END;
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_sesion_docente_paginado.sql
-- ============================================================================
-- usp_consultar_solicitudes_sesion_docente_paginado (ATA D6, HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET paginado (PAG_001 + totalRegistros).
-- Solicitudes de sesion extraordinaria de los grupos donde el ejecutor es docente titular (uv_solicitud_sesion). Mismas columnas y
-- mismo orden que usp_consultar_solicitudes_sesion_coordinador_paginado (incluido idPrograma/nombrePrograma: el programa
-- alfabeticamente primero del grupo, una fila por sesion), fechaSolicitudUtc DESC. @soloPendientes = 1 (por defecto) deja las
-- solicitudes en espera de aval que no fueron canceladas; 0 incluye aprobadas, rechazadas y canceladas. @idGrupo ajeno: sin filas.
-- Validacion compartida (correlacion, ejecutor, RBAC DOCENTE, PAG_001) en usp_validar_consulta_paginada_interno; THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_sesion_docente_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @soloPendientes BIT              = 1,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @numeroPagina   INT              = 1,
    @tamanoPagina   INT              = 20,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuarioValidado       UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'DOCENTE',
        @numeroPagina = @numeroPagina, @tamanoPagina = @tamanoPagina,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  v.*, totalRegistros = COUNT(*) OVER()
    FROM    dbo.uv_solicitud_sesion v
    WHERE   v.idDocente IN (SELECT d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioValidado)
      AND   (@idGrupo IS NULL OR v.idGrupo = @idGrupo)
      AND   (ISNULL(@soloPendientes, 1) = 0 OR v.pendienteAprobacion = 1)
      AND   v.idPrograma = (SELECT TOP 1 x.idPrograma FROM dbo.uv_solicitud_sesion x WHERE x.idSesion = v.idSesion ORDER BY x.nombrePrograma, x.idPrograma)
    ORDER BY v.fechaSolicitudUtc DESC, v.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_calendario_estudiante.sql
-- ============================================================================
-- usp_consultar_sesiones_calendario_estudiante (ATA D7)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (sin paginacion: rango maximo de 31 dias).
-- Sesiones de los grupos con matricula inscrita del estudiante cuyo inicio cae entre @desde y @hasta (ambos inclusivos, fecha LOCAL
-- institucional), una fila por sesion de uv_sesion_calendario (solicitudes pendientes o rechazadas excluidas), ordenadas por inicio.
-- @hasta >= @desde y maximo 31 dias; si no, CAL_001. Validacion compartida en usp_validar_rango_calendario_interno (perfil
-- ESTUDIANTE); THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_calendario_estudiante]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @desde          DATE,
    @hasta          DATE,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuarioValidado       UNIQUEIDENTIFIER;
    DECLARE @desdeUtc                DATETIME2(7);
    DECLARE @hastaUtcExclusivo       DATETIME2(7);
    DECLARE @codigoInscrita          NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_rango_calendario_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'ESTUDIANTE',
        @desde = @desde, @hasta = @hasta,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @desdeUtc = @desdeUtc OUTPUT, @hastaUtcExclusivo = @hastaUtcExclusivo OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  c.idSesion, c.idGrupo, c.codigoGrupo, c.nombreGrupo, c.idAsignatura, c.codigoAsignatura, c.nombreAsignatura,
            c.idDocente, c.nombreDocente, c.fechaHoraInicioUtc, c.fechaHoraFinUtc, c.esExtraordinaria, c.estaCancelada,
            c.motivoCancelacion, c.esCancelacionAutomatica, c.nombreDiaFestivo
    FROM    dbo.uv_sesion_calendario c
    WHERE   c.fechaHoraInicioUtc >= @desdeUtc AND c.fechaHoraInicioUtc < @hastaUtcExclusivo
      AND   c.idGrupo IN (SELECT eg.grupo
                          FROM dbo.EstudianteGrupo eg
                          INNER JOIN dbo.Estudiante est ON est.id = eg.estudiante
                          INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                          WHERE est.usuario = @idUsuarioValidado AND ee.codigo = @codigoInscrita)
    ORDER BY c.fechaHoraInicioUtc ASC, c.idSesion ASC;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_calendario_docente.sql
-- ============================================================================
-- usp_consultar_sesiones_calendario_docente (ATA D7)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (sin paginacion: rango maximo de 31 dias).
-- Sesiones de los grupos donde el ejecutor es docente titular cuyo inicio cae entre @desde y @hasta (ambos inclusivos, fecha LOCAL
-- institucional), con las mismas columnas y orden que usp_consultar_sesiones_calendario_estudiante. @hasta >= @desde y maximo 31
-- dias; si no, CAL_001. Validacion compartida en usp_validar_rango_calendario_interno (perfil DOCENTE); THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_calendario_docente]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @desde          DATE,
    @hasta          DATE,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuarioValidado       UNIQUEIDENTIFIER;
    DECLARE @desdeUtc                DATETIME2(7);
    DECLARE @hastaUtcExclusivo       DATETIME2(7);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_rango_calendario_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'DOCENTE',
        @desde = @desde, @hasta = @hasta,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @desdeUtc = @desdeUtc OUTPUT, @hastaUtcExclusivo = @hastaUtcExclusivo OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  c.idSesion, c.idGrupo, c.codigoGrupo, c.nombreGrupo, c.idAsignatura, c.codigoAsignatura, c.nombreAsignatura,
            c.idDocente, c.nombreDocente, c.fechaHoraInicioUtc, c.fechaHoraFinUtc, c.esExtraordinaria, c.estaCancelada,
            c.motivoCancelacion, c.esCancelacionAutomatica, c.nombreDiaFestivo
    FROM    dbo.uv_sesion_calendario c
    WHERE   c.fechaHoraInicioUtc >= @desdeUtc AND c.fechaHoraInicioUtc < @hastaUtcExclusivo
      AND   c.idDocente IN (SELECT d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioValidado)
    ORDER BY c.fechaHoraInicioUtc ASC, c.idSesion ASC;
END;
GO
-- ---- schema/seed/68_ata_mensajes_calendario.sql
-- ATA D7: mensaje del rango del calendario de sesiones (horario semanal con fechas). Idempotente (MERGE por codigo).
--   CAL_001  el rango no es valido: debe tener ambas fechas, hasta >= desde y como maximo 31 dias (el texto de usuario no lleva parametros)
-- Migracion: 52_ata_solicitudes_docente_calendario_up.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('CAL_001', 'VALIDATION_ERROR', 'BAJO', N'El rango de fechas no es válido: indique inicio y fin, con el fin igual o posterior y máximo 31 días.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('CAL_001', 'VALIDATION_ERROR', 'BAJO', N'ATA D7: rango [{}] a [{}] inválido (fechas ausentes, hasta < desde o más de {} días).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/security/rol_asistencias_runtime_ata_p2.sql
-- ATA D6/D7: permisos del rol runtime sobre las solicitudes de sesion del docente y el calendario de sesiones. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_docente_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_sesion_docente_paginado] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_calendario_estudiante] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_docente', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_calendario_docente] TO [rol_asistencias_runtime];
IF OBJECT_ID(N'dbo.uv_sesion_calendario', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_calendario] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 52 UP OK';
GO
