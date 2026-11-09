USE [gestionasistenciadb];
GO
SET QUOTED_IDENTIFIER ON;
GO

/*
  Isolated Java-integration fixture for MAINT-003G.
  It is not deployment seed data: it is executed explicitly only against the
  controlled Developer SQL Server container. The public procedures under test
  create the session and attendance rows; direct DELETE is used solely to make
  repeated preparation idempotent.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'gestionasistenciadb'
   OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE N'%Developer Edition%'
    THROW 52208, 'BLOCKED - MAINT-003G fixtures require gestionasistenciadb on SQL Server Developer Edition.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 52209, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;

DECLARE @fixtureName NVARCHAR(50) = N'IT-MAINT003G-ATTENDANCE';
DECLARE @group UNIQUEIDENTIFIER;
DECLARE @teacherUser UNIQUEIDENTIFIER;
DECLARE @session UNIQUEIDENTIFIER;
DECLARE @attendanceJson NVARCHAR(MAX);
DECLARE @correlation UNIQUEIDENTIFIER = NEWID();
DECLARE @attendanceCorrelation UNIQUEIDENTIFIER = NEWID();
DECLARE @existingSessionCount INT;
-- SES-01: el registro ordinario solo se acepta con la sesion activa y procedencia UTC confirmada, por eso la
-- sesion del fixture se crea con el contrato v2 (UTC_V2) abierta en el instante de preparacion.
DECLARE @sessionStartUtc DATETIME2 = DATEADD(MINUTE, -30, SYSUTCDATETIME());
DECLARE @sessionEndUtc DATETIME2 = DATEADD(HOUR, 2, SYSUTCDATETIME());
DECLARE @result TABLE (
    idCorrelacion UNIQUEIDENTIFIER,
    mensajeUsuarioResultado NVARCHAR(4000),
    mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT
);

BEGIN TRANSACTION;

-- Resolve the existing fixture through public read views, then delete only rows keyed to that session.
-- SQL Server 2022 raises error 8624 for the original multi-table DELETE plans, so dependencies are materialized
-- through views and deleted one exact foreign key at a time. A linked review request is preserved and stops cleanup.
SELECT @existingSessionCount = COUNT(*) FROM dbo.uv_sesion WHERE nombre = @fixtureName;
IF @existingSessionCount > 1
    THROW 52200, 'MAINT-003G fixture found duplicate sessions with its reserved name.', 1;
SELECT @session = id FROM dbo.uv_sesion WHERE nombre = @fixtureName;

IF EXISTS (
    SELECT 1
    FROM dbo.uv_solicitud_revision_asistencia r
    INNER JOIN dbo.uv_asistencia a ON a.id = r.idAsistencia
    WHERE a.idSesion = @session
)
    THROW 52207, 'MAINT-003G fixture has linked review requests; cleanup was stopped.', 1;

CREATE TABLE #attendanceIds (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #attendanceIds (id)
SELECT a.id FROM dbo.uv_asistencia a WHERE a.idSesion = @session;

DECLARE @attendanceId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #attendanceIds)
BEGIN
    SELECT TOP (1) @attendanceId = id FROM #attendanceIds ORDER BY id;
    DELETE FROM dbo.DetalleAsistencia WHERE asistencia = @attendanceId;
    DELETE FROM #attendanceIds WHERE id = @attendanceId;
END;

-- CULM-001 B.2 ([SUPUESTO-B-20]): el lote congelado crea la toma 1 implicita; orden DetalleAsistencia -> TokenAsistenciaToma ->
-- TomaAsistencia -> SesionCancelacion -> Asistencia -> Sesion (en linea: este fixture se ejecuta fuera de test_suite.sql).
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL
BEGIN
    CREATE TABLE #takeIds (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
    INSERT INTO #takeIds (id)
    SELECT t.idToma FROM dbo.uv_toma_asistencia t WHERE t.idSesion = @session;

    DECLARE @takeId UNIQUEIDENTIFIER;
    WHILE EXISTS (SELECT 1 FROM #takeIds)
    BEGIN
        SELECT TOP (1) @takeId = id FROM #takeIds ORDER BY id;
        IF OBJECT_ID(N'dbo.TokenAsistenciaToma', N'U') IS NOT NULL
            DELETE FROM dbo.TokenAsistenciaToma WHERE toma = @takeId;
        DELETE FROM dbo.TomaAsistencia WHERE id = @takeId;
        DELETE FROM #takeIds WHERE id = @takeId;
    END;
    DROP TABLE #takeIds;
END
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NOT NULL
    DELETE FROM dbo.SesionCancelacion WHERE sesion = @session;

DELETE FROM dbo.Asistencia WHERE sesion = @session;

DELETE FROM dbo.Sesion WHERE id = @session;
DROP TABLE #attendanceIds;
SET @session = NULL;

SELECT TOP (1)
    @group = g.id,
    @teacherUser = d.idUsuario
FROM dbo.uv_grupo g
INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = g.id AND eg.codigoEstadoEstudiante = N'A'
GROUP BY g.id, d.idUsuario
HAVING COUNT(*) >= 2
ORDER BY g.id;

IF @group IS NULL OR @teacherUser IS NULL
    THROW 52201, 'MAINT-003G fixture requires one teacher-owned group with two active students.', 1;

INSERT INTO @result
EXEC dbo.usp_crear_sesion_v2
    @idGrupo = @group,
    @nombre = @fixtureName,
    @fechaHoraInicio = @sessionStartUtc,
    @fechaHoraFin = @sessionEndUtc,
    @idCorrelacion = @correlation,
    @idUsuarioEjecutor = @teacherUser;

IF NOT EXISTS (SELECT 1 FROM @result WHERE estadoResultado = 1)
    THROW 52202, 'MAINT-003G fixture session creation was rejected by the public contract.', 1;

SELECT @session = id FROM dbo.uv_sesion WHERE nombre = @fixtureName;
IF @session IS NULL
    THROW 52203, 'MAINT-003G fixture session was not persisted.', 1;

SELECT @attendanceJson = CONCAT(
    '[',
    STRING_AGG(CONCAT('{"idEstudiante":"', CONVERT(VARCHAR(36), q.idEstudiante), '","estado":"', q.estado, '"}'), ','),
    ']')
FROM (
    SELECT TOP (2) eg.idEstudiante, CASE ROW_NUMBER() OVER (ORDER BY eg.idEstudiante)
        WHEN 1 THEN 'AN' ELSE 'SJC' END AS estado
    FROM dbo.uv_estudiante_grupo eg
    WHERE eg.idGrupo = @group AND eg.codigoEstadoEstudiante = N'A'
    ORDER BY eg.idEstudiante
) q;

IF @attendanceJson IS NULL OR @attendanceJson = '[]'
    THROW 52204, 'MAINT-003G fixture did not resolve two active students.', 1;

DELETE FROM @result;
INSERT INTO @result
EXEC dbo.usp_registrar_asistencias_sesion
    @idSesion = @session,
    @asistenciaJSON = @attendanceJson,
    @idCorrelacion = @attendanceCorrelation,
    @idUsuarioEjecutor = @teacherUser;

IF NOT EXISTS (SELECT 1 FROM @result WHERE estadoResultado = 1)
    THROW 52205, 'MAINT-003G fixture attendance registration was rejected by the public contract.', 1;

IF (SELECT COUNT(*) FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    WHERE a.idSesion = @session) <> 2
    THROW 52206, 'MAINT-003G fixture must expose exactly two attendance-detail rows.', 1;

COMMIT TRANSACTION;

SELECT CONCAT('TEST_FIXTURE_READY|session=', CONVERT(VARCHAR(36), @session), '|rows=2');
GO
