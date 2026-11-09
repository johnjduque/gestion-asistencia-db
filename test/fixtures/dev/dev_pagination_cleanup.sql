USE [gestionasistenciadb];
GO
SET QUOTED_IDENTIFIER ON;
GO
/*
  MAINT-003K - limpieza de los fixtures sinteticos de desarrollo (paginacion).
  Retira filas DE0000 y dependientes resueltas por sus claves foráneas (ver dev_pagination_fixture.sql).
  Idempotente. NO es un seed de despliegue: se ejecuta solo con deploy_dev_fixtures.ps1 contra un contenedor Developer.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE 'Developer%'
    THROW 55001, 'BLOCKED - dev fixtures only run on SQL Server Developer Edition.', 1;
IF DB_NAME() <> N'gestionasistenciadb'
    THROW 55002, 'BLOCKED - unexpected database for dev fixtures.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 55003, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;

BEGIN TRANSACTION;

-- This fixture owns only DE0000 groups. Refuse to remove a DE0000 teacher while another fixture still uses it.
IF EXISTS (
    SELECT 1
    FROM dbo.uv_grupo
    WHERE LEFT(CONVERT(CHAR(36), idDocente), 6) = 'DE0000'
      AND LEFT(CONVERT(CHAR(36), id), 6) <> 'DE0000'
)
    THROW 55005, 'ABORT - a non-DE0000 group references a fixture teacher; clean its owning fixture first.', 1;

-- Include attendance created through public procedures when its ID is random but its student-group or session
-- belongs to the reserved DE0000 fixture. Resolve those keys through views and delete one exact key at a time.
CREATE TABLE #fixtureAttendance (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #fixtureAttendance (id)
SELECT a.id
FROM dbo.uv_asistencia a
WHERE LEFT(CONVERT(CHAR(36), a.id), 6) = 'DE0000'
   OR LEFT(CONVERT(CHAR(36), a.idEstudianteGrupo), 6) = 'DE0000'
   OR LEFT(CONVERT(CHAR(36), a.idSesion), 6) = 'DE0000';

DECLARE @attendanceId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #fixtureAttendance)
BEGIN
    SELECT TOP (1) @attendanceId = id FROM #fixtureAttendance ORDER BY id;
    IF EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia WHERE idAsistencia = @attendanceId)
        THROW 55004, 'ABORT - a DE0000 fixture attendance row has a review request; cleanup preserves it.', 1;
    DELETE FROM dbo.DetalleAsistencia WHERE asistencia = @attendanceId;
    DELETE FROM dbo.Asistencia WHERE id = @attendanceId;
    DELETE FROM #fixtureAttendance WHERE id = @attendanceId;
END;
DROP TABLE #fixtureAttendance;

CREATE TABLE #fixtureSessions (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #fixtureSessions (id)
SELECT s.id
FROM dbo.uv_sesion s
WHERE LEFT(CONVERT(CHAR(36), s.id), 6) = 'DE0000'
   OR LEFT(CONVERT(CHAR(36), s.idGrupo), 6) = 'DE0000';

-- CULM-001 B.2 ([SUPUESTO-B-20]): tokens, tomas y cancelaciones de las sesiones del fixture antes de borrarlas.
-- Materialize take IDs through the view one session at a time, then delete by exact IDs.
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL
BEGIN
    CREATE TABLE #fixtureTakes (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
    CREATE TABLE #fixtureSessionScan (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
    INSERT INTO #fixtureSessionScan (id) SELECT id FROM #fixtureSessions;

    DECLARE @scanSessionId UNIQUEIDENTIFIER;
    WHILE EXISTS (SELECT 1 FROM #fixtureSessionScan)
    BEGIN
        SELECT TOP (1) @scanSessionId = id FROM #fixtureSessionScan ORDER BY id;
        INSERT INTO #fixtureTakes (id)
        SELECT t.idToma FROM dbo.uv_toma_asistencia t WHERE t.idSesion = @scanSessionId;
        DELETE FROM #fixtureSessionScan WHERE id = @scanSessionId;
    END;
    DROP TABLE #fixtureSessionScan;

    DECLARE @takeId UNIQUEIDENTIFIER;
    WHILE EXISTS (SELECT 1 FROM #fixtureTakes)
    BEGIN
        SELECT TOP (1) @takeId = id FROM #fixtureTakes ORDER BY id;
        IF OBJECT_ID(N'dbo.TokenAsistenciaToma', N'U') IS NOT NULL
            DELETE FROM dbo.TokenAsistenciaToma WHERE toma = @takeId;
        DELETE FROM dbo.TomaAsistencia WHERE id = @takeId;
        DELETE FROM #fixtureTakes WHERE id = @takeId;
    END;
    DROP TABLE #fixtureTakes;
END;

DECLARE @sessionId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #fixtureSessions)
BEGIN
    SELECT TOP (1) @sessionId = id FROM #fixtureSessions ORDER BY id;
    IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NOT NULL
        DELETE FROM dbo.SesionCancelacion WHERE sesion = @sessionId;
    DELETE FROM dbo.SesionProcedenciaClasificacion WHERE sesion = @sessionId;
    DELETE FROM dbo.Sesion WHERE id = @sessionId;
    DELETE FROM #fixtureSessions WHERE id = @sessionId;
END;
DROP TABLE #fixtureSessions;

-- Delete fixture enrollments by exact keys, including any random-ID enrollment attached to a DE0000 group.
CREATE TABLE #fixtureStudentGroups (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #fixtureStudentGroups (id)
SELECT eg.id
FROM dbo.uv_estudiante_grupo eg
WHERE LEFT(CONVERT(CHAR(36), eg.id), 6) = 'DE0000'
   OR LEFT(CONVERT(CHAR(36), eg.idGrupo), 6) = 'DE0000';
DECLARE @studentGroupId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #fixtureStudentGroups)
BEGIN
    SELECT TOP (1) @studentGroupId = id FROM #fixtureStudentGroups ORDER BY id;
    DELETE FROM dbo.EstudianteGrupo WHERE id = @studentGroupId;
    DELETE FROM #fixtureStudentGroups WHERE id = @studentGroupId;
END;
DROP TABLE #fixtureStudentGroups;
CREATE TABLE #fixtureSchedules (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #fixtureSchedules (id)
SELECT h.id FROM dbo.uv_horario_docente h WHERE LEFT(CONVERT(CHAR(36), h.idGrupo), 6) = 'DE0000';
DECLARE @scheduleId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #fixtureSchedules)
BEGIN
    SELECT TOP (1) @scheduleId = id FROM #fixtureSchedules ORDER BY id;
    DELETE FROM dbo.Horario WHERE id = @scheduleId;
    DELETE FROM #fixtureSchedules WHERE id = @scheduleId;
END;
DROP TABLE #fixtureSchedules;
DELETE FROM dbo.Grupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.EstudiantePrograma WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
-- Remove exact program links resolved through the public view before deleting their fixture teachers.
CREATE TABLE #fixtureDocentePrograms (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO #fixtureDocentePrograms (id)
SELECT dp.idDocentePrograma
FROM dbo.uv_docente_programa dp
WHERE LEFT(CONVERT(CHAR(36), dp.idDocente), 6) = 'DE0000';
DECLARE @docenteProgramaId UNIQUEIDENTIFIER;
WHILE EXISTS (SELECT 1 FROM #fixtureDocentePrograms)
BEGIN
    SELECT TOP (1) @docenteProgramaId = id FROM #fixtureDocentePrograms ORDER BY id;
    DELETE FROM dbo.DocentePrograma WHERE id = @docenteProgramaId;
    DELETE FROM #fixtureDocentePrograms WHERE id = @docenteProgramaId;
END;
DROP TABLE #fixtureDocentePrograms;
DELETE FROM dbo.Docente WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Usuario WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';

COMMIT TRANSACTION;
PRINT 'DEV_FIXTURE_CLEANUP_OK';
GO
