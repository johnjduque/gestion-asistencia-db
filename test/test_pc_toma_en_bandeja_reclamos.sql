USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- PC (mejora 2026-11-12, migracion 38): la bandeja del docente (usp_consultar_solicitudes_revision_docente, R2) trae AL FINAL idToma,
-- numeroToma y fechaPuntoControlUtc de la toma reclamada (NULL en un reclamo de la sesion completa), como el detalle del docente.
--   PC_BAN_01_TOMA_EN_BANDEJA          reclamo de una toma: idToma, numeroToma y fechaPuntoControlUtc iguales a los del detalle
--   PC_BAN_02_SESION_COMPLETA_NULL     reclamo de la sesion completa: las tres columnas en NULL
--   PC_BAN_03_COLUMNAS_AL_FINAL        las tres columnas son las ultimas (29..31) y totalSoportes sigue en la 28
--   PC_BAN_04_AMBITO_Y_SIN_DUPLICADOS  una fila por reclamo (sin multiplicar) y otro docente no ve nada
--   PC_BAN_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida. Requiere el helper test/fixtures/culm001_b2_toma_fixture.sql (test_suite.sql).
PRINT 'TEST START: test_pc_toma_en_bandeja_reclamos (PC, mejora bandeja)';
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NULL OR OBJECT_ID(N'dbo.uv_toma_punto_control', N'V') IS NULL
    THROW 58300, 'TEST FAILED PC_BAN_00: falta la migracion 37 (SolicitudRevisionAsistencia.toma o uv_toma_punto_control).', 1;
GO

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @teacher2 UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentB UNIQUEIDENTIFIER, @egA UNIQUEIDENTIFIER, @egB UNIQUEIDENTIFIER;
DECLARE @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER, @estadoP UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente
FROM dbo.Grupo g
WHERE (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A') >= 2
ORDER BY (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id) ASC, g.id;
SELECT @studentA = z.idEstudiante, @egA = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 1;
SELECT @studentB = z.idEstudiante, @egB = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 2;
SELECT TOP 1 @teacher2 = d.id FROM dbo.Docente d WHERE d.id <> @teacher ORDER BY d.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT @userT2 = usuario FROM dbo.Docente WHERE id = @teacher2;
SELECT @estadoP = id FROM dbo.Estado WHERE codigo = 'P';
IF @group IS NULL OR @teacher IS NULL OR @teacher2 IS NULL OR @studentA IS NULL OR @studentB IS NULL OR @egA IS NULL OR @egB IS NULL
   OR @userT IS NULL OR @userT2 IS NULL OR @estadoP IS NULL
    THROW 58301, 'TEST FAILED PC_BAN: faltan fixtures del seed (grupo con dos estudiantes, dos docentes, estado P).', 1;

DECLARE @session UNIQUEIDENTIFIER = NEWID(), @asisA UNIQUEIDENTIFIER = NEWID(), @asisB UNIQUEIDENTIFIER = NEWID();
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @inicio DATETIME2(7) = '2026-10-19T15:30:00';
DECLARE @reqToma UNIQUEIDENTIFIER = NEWID(), @reqSesion UNIQUEIDENTIFIER = NEWID(), @toma UNIQUEIDENTIFIER;
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @rows INT;

CREATE TABLE #banR (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT,
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), totalSoportes INT,
    idToma UNIQUEIDENTIFIER, numeroToma SMALLINT, fechaPuntoControlUtc DATETIME2(7));
CREATE TABLE #banD (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    asistio BIT, codigoRazonCausa NVARCHAR(5), nombreRazonCausa NVARCHAR(50),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7),
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), soportesJson NVARCHAR(MAX),
    idToma UNIQUEIDENTIFIER, numeroToma SMALLINT, fechaPuntoControlUtc DATETIME2(7), codigoResultadoAprobacion NVARCHAR(10),
    codigoRazonCausaToma NVARCHAR(10), minutosSesion INT, minutosAsistidos INT);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA PC BAN', @number, @sessionCode, 1, @group, @inicio, DATEADD(HOUR, 1, @inicio));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asisA, @egA, @session);
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asisB, @egB, @session);
    EXEC #culm001_b2_crear_toma @idSesion = @session, @idToma = @toma OUTPUT;
    -- A reclama la toma 1; B reclama la sesion completa (legado, sin toma)
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta, toma)
    VALUES (@reqToma, N'QA-PCBAN-T', @asisA, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'Reclamo de una toma QA', '', @toma);
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reqSesion, N'QA-PCBAN-S', @asisB, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'Reclamo de la sesion QA', '');

    INSERT INTO #banR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100;
    INSERT INTO #banD EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @reqToma, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;

    -- PC_BAN_01: la toma reclamada llega con numero y punto de control, iguales a los del detalle
    SET @ok = IIF(EXISTS (SELECT 1 FROM #banR r INNER JOIN #banD d ON d.idSolicitudRevisionAsistencia = r.idSolicitudRevisionAsistencia
                          WHERE r.idSolicitudRevisionAsistencia = @reqToma AND r.idToma = @toma AND r.numeroToma = 1
                            AND r.fechaPuntoControlUtc IS NOT NULL AND r.idToma = d.idToma AND r.numeroToma = d.numeroToma
                            AND r.fechaPuntoControlUtc = d.fechaPuntoControlUtc), 1, 0);
    IF @ok <> 1 THROW 58302, 'TEST FAILED: PC_BAN_01_TOMA_EN_BANDEJA', 1;
    PRINT 'TEST_PASS:PC_BAN_01_TOMA_EN_BANDEJA';

    -- PC_BAN_02: el reclamo de la sesion completa conserva las tres columnas en NULL
    SET @ok = IIF(EXISTS (SELECT 1 FROM #banR WHERE idSolicitudRevisionAsistencia = @reqSesion
                          AND idToma IS NULL AND numeroToma IS NULL AND fechaPuntoControlUtc IS NULL), 1, 0);
    IF @ok <> 1 THROW 58303, 'TEST FAILED: PC_BAN_02_SESION_COMPLETA_NULL', 1;
    PRINT 'TEST_PASS:PC_BAN_02_SESION_COMPLETA_NULL';

    -- PC_BAN_03: columnas AL FINAL (contrato posicional): totalSoportes en la 28 y las tres nuevas en la 29, 30 y 31 (ultimas)
    SET @ok = IIF((SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), NULL) d
                   WHERE (d.name = 'totalRegistros' AND d.column_ordinal = 25) OR (d.name = 'totalSoportes' AND d.column_ordinal = 28)
                      OR (d.name = 'idToma' AND d.column_ordinal = 29) OR (d.name = 'numeroToma' AND d.column_ordinal = 30)
                      OR (d.name = 'fechaPuntoControlUtc' AND d.column_ordinal = 31)) = 5
              AND (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), NULL)) = 31, 1, 0);
    IF @ok <> 1 THROW 58304, 'TEST FAILED: PC_BAN_03_COLUMNAS_AL_FINAL', 1;
    PRINT 'TEST_PASS:PC_BAN_03_COLUMNAS_AL_FINAL';

    -- PC_BAN_04: una fila por reclamo (el LEFT JOIN a la toma no multiplica) y otro docente no ve los reclamos
    SELECT @rows = COUNT(*) FROM #banR WHERE idSolicitudRevisionAsistencia IN (@reqToma, @reqSesion);
    DELETE FROM #banR;
    INSERT INTO #banR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(@rows = 2 AND NOT EXISTS (SELECT 1 FROM #banR WHERE idSolicitudRevisionAsistencia IN (@reqToma, @reqSesion)), 1, 0);
    IF @ok <> 1 THROW 58305, 'TEST FAILED: PC_BAN_04_AMBITO_Y_SIN_DUPLICADOS', 1;
    PRINT 'TEST_PASS:PC_BAN_04_AMBITO_Y_SIN_DUPLICADOS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #banR;
    DROP TABLE IF EXISTS #banD;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #banR;
DROP TABLE IF EXISTS #banD;
GO

IF @@TRANCOUNT <> 0
    THROW 58306, 'TEST FAILED: PC_BAN_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:PC_BAN_TRANCOUNT_ZERO';
PRINT 'TEST PASS: test_pc_toma_en_bandeja_reclamos';
GO
