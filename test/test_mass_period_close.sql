USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
-- CULM-001 C.1 (CONTRACT §2.13.2): la asignatura y los estudiantes son del programa A sembrado (con coordinador), para que la
-- propuesta de cancelacion tenga un resolutor competente; el docente titular no es coordinador ni decano.
DECLARE @assignment UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
DECLARE @progQa UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 di.id FROM dbo.uv_docente_identidad di
    WHERE di.estaActivoUsuario = 1 AND di.idUsuario NOT IN (SELECT usuario FROM dbo.Coordinador UNION SELECT usuario FROM dbo.Decano) ORDER BY di.id);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @coordUser UNIQUEIDENTIFIER = (SELECT c.usuario FROM dbo.Programa p INNER JOIN dbo.Coordinador c ON c.id = p.coordinador WHERE p.id = @progQa);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @studentAbsent UNIQUEIDENTIFIER, @studentPresent UNIQUEIDENTIFIER;
SELECT @studentAbsent = estudiante FROM (SELECT estudiante, ROW_NUMBER() OVER (ORDER BY estudiante) AS rn FROM dbo.EstudiantePrograma WHERE programa = @progQa) e WHERE rn = 1;
SELECT @studentPresent = estudiante FROM (SELECT estudiante, ROW_NUMBER() OVER (ORDER BY estudiante) AS rn FROM dbo.EstudiantePrograma WHERE programa = @progQa) e WHERE rn = 2;
IF @studentPresent IS NULL SET @studentPresent = @studentAbsent;
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @finished UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F');
DECLARE @cancelled UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI');
DECLARE @absence UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @enrollment UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 600000 + ABS(CHECKSUM(NEWID()) % 100000);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @baseDetailCode INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @coordUser IS NULL OR
   @adminUser IS NULL OR
   @studentAbsent IS NULL OR @studentPresent IS NULL OR @active IS NULL OR
   @finished IS NULL OR @cancelled IS NULL OR @absence IS NULL
    THROW 52010, 'TEST FAILED: MASS_CLOSE fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Cierre', @periodCode,
        DATEADD(DAY, -20, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Masivo', 30, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (@enrollment, @active, @studentAbsent, @group),
        (NEWID(), @active, @studentPresent, @group);

    DECLARE @firstDay DATE = DATEADD(DAY, -10, CAST(GETDATE() AS DATE));
    DECLARE @sessions TABLE (seq INT PRIMARY KEY, sessionId UNIQUEIDENTIFIER, attendanceId UNIQUEIDENTIFIER);
    INSERT INTO @sessions VALUES
        (1, NEWID(), NEWID()), (2, NEWID(), NEWID()), (3, NEWID(), NEWID());
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT sessionId, CONCAT(N'QA Cierre ', seq), seq,
        LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        DATEADD(HOUR, 9, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))), N'UTC_V2'
    FROM @sessions;
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT attendanceId, @enrollment, sessionId FROM @sessions;
    -- CULM-001 B.2 ([SUPUESTO-B-20]): la columna obligatoria DetalleAsistencia.toma exige la toma 1 de la sesion (helper culm001_b2_toma_fixture.sql).
    DECLARE @culmb2Sesiones NVARCHAR(MAX) = (SELECT idSesion = sessionId FROM @sessions FOR JSON PATH);
    EXEC #culm001_b2_crear_tomas @sesionesJSON = @culmb2Sesiones;
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma)
    SELECT NEWID(), @baseDetailCode + seq, attendanceId, 0, @absence,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        DATEADD(HOUR, 9, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        (SELECT t.id FROM dbo.TomaAsistencia t WHERE t.sesion = sessionId AND t.numero = 1)
    FROM @sessions;

    -- CULM-001 C.1 (DEC-041 C-10, N-1): el cierre ya no escribe CI por conteo. Fase 1: con el motor activo, la matricula con 3 SJC
    -- (100 % por horas) y sin revision bloquea el cierre (RCN_012) sin crear la revision ni cambiar matriculas ni contadores.
    IF OBJECT_ID(N'tempdb..#mcFase1') IS NOT NULL DROP TABLE #mcFase1;
    CREATE TABLE #mcFase1 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    INSERT INTO #mcFase1 EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF NOT EXISTS (SELECT 1 FROM #mcFase1 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%RCN_012%')
        THROW 52030, 'TEST FAILED: MASS_CLOSE_SUCCESS fase 1: con una perdida sin revision el cierre debe responder RCN_012.', 1;
    IF EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @enrollment)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @enrollment AND estado = @active)
       OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group AND cantidadEstudiantesFinalizaron = 0 AND cantidadEstudiantesCancelaronAutomaticamente = 0)
        THROW 52031, 'TEST FAILED: MASS_CLOSE_SUCCESS fase 1: el cierre bloqueado no debe crear la revision ni cambiar matriculas ni contadores.', 1;
    DROP TABLE #mcFase1;
    -- Fase 2: el motor (backend) crea la revision; el titular propone y el coordinador del programa aprueba (CI solo nace asi).
    DECLARE @mcEv TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, ac INT, asup INT, are INT, rc INT, nov NVARCHAR(MAX));
    INSERT INTO @mcEv EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @group, @idCorrelacion = @corr, @idEstudianteGrupo = NULL;
    DECLARE @mcRev UNIQUEIDENTIFIER = (SELECT id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @enrollment);
    DECLARE @mcDec TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idRev UNIQUEIDENTIFIER, ea NVARCHAR(20), en NVARCHAR(20), cd NVARCHAR(20), sc BIT,
        idGrupo UNIQUEIDENTIFIER, idEg UNIQUEIDENTIFIER, idEst UNIQUEIDENTIFIER, pct DECIMAL(5,2), plantilla VARCHAR(60), perfil NVARCHAR(20), esc BIT);
    INSERT INTO @mcDec EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @mcRev, @codigoDecision = N'PROPONER', @motivo = N'Tres inasistencias sin justa causa', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    DECLARE @mcRes TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idRev UNIQUEIDENTIFIER, ea NVARCHAR(20), en NVARCHAR(20), cd NVARCHAR(20), sc BIT, cm BIT,
        idGrupo UNIQUEIDENTIFIER, idEg UNIQUEIDENTIFIER, idEst UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER, perfil NVARCHAR(20), pct DECIMAL(5,2), plantilla VARCHAR(60));
    INSERT INTO @mcRes EXEC dbo.usp_resolver_revision_cancelacion @idRevision = @mcRev, @codigoDecision = N'APROBAR', @motivo = N'Se aprueba la cancelacion por inasistencia', @idCorrelacion = @corr, @idUsuarioEjecutor = @coordUser;
    IF NOT EXISTS (SELECT 1 FROM @mcRes WHERE estado = 1 AND cm = 1)
        THROW 52032, 'TEST FAILED: MASS_CLOSE_SUCCESS fase 2: la aprobacion del coordinador debe cancelar la matricula (CI).', 1;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'CierreMasivoPeriodo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:MASS_CLOSE_SUCCESS|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:MASS_CLOSE_SUCCESS|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:MASS_CLOSE_SUCCESS';
    EXEC dbo.usp_ejecutar_cierre_masivo_periodo
        @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @adminUser;
    PRINT 'TEST_RESULT_END:MASS_CLOSE_SUCCESS';
    IF @@TRANCOUNT <> 1
        THROW 52011, 'TEST FAILED: MASS_CLOSE_SUCCESS destroyed the caller transaction.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo
        WHERE id = @enrollment AND codigoEstadoEstudiante = 'CI')
        THROW 52012, 'TEST FAILED: MASS_CLOSE_SUCCESS la matricula con cancelacion aprobada debe seguir en CI tras el cierre.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo
        WHERE estudiante = @studentPresent AND grupo = @group AND estado = @finished)
        THROW 52013, 'TEST FAILED: MASS_CLOSE_SUCCESS did not finish active student.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo
        WHERE id = @group AND cantidadEstudiantesFinalizaron = 1
        AND cantidadEstudiantesCancelaronAutomaticamente = 1)
        THROW 52014, 'TEST FAILED: MASS_CLOSE_SUCCESS counters incorrect.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento
        WHERE correlationId = @corr AND resourceId = CONVERT(NVARCHAR(50), @period)
        AND action = N'CIERRE_MASIVO_PERIODO' AND result = N'SUCCESS' AND actorType = N'USER'
        AND ISJSON(metadata) = 1)
        THROW 52015, 'TEST FAILED: MASS_CLOSE_SUCCESS missing audit event.', 1;
    PRINT 'TEST_STATE_PASS:MASS_CLOSE_SUCCESS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group) OR
   EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @period) OR
   EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr)
    THROW 52016, 'TEST FAILED: MASS_CLOSE leaked fixtures.', 1;
IF @@TRANCOUNT <> 0 THROW 52017, 'TEST FAILED: MASS_CLOSE left transaction open.', 1;
GO

-- CULM-001 C.1 (CONTRACT §2.13.2, DEC-041 C-10; antes CULM001_B2_HOR_10 de B.2): el cierre masivo decide por HORAS, no por conteo
-- de sesiones. Un estudiante con una falta (toma 1) en cada una de 3 sesiones de 3 h y otro con 3 tomas ausentes de UNA sola
-- sesion quedan en 33 % por horas: sin revision el cierre responde RCN_012 (2 perdidas sin revision) y no crea revisiones ni cambia
-- estados; el motor crea las 2 revisiones, el titular las pasa a MANTENIDA y el cierre termina con ambas en F (no hay CI por conteo).
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
DECLARE @progQa UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 di.id FROM dbo.uv_docente_identidad di
    WHERE di.estaActivoUsuario = 1 AND di.idUsuario NOT IN (SELECT usuario FROM dbo.Coordinador UNION SELECT usuario FROM dbo.Decano) ORDER BY di.id);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @stTresSesiones UNIQUEIDENTIFIER, @stUnaSesion UNIQUEIDENTIFIER;
SELECT @stTresSesiones = estudiante FROM (SELECT estudiante, ROW_NUMBER() OVER (ORDER BY estudiante) AS rn FROM dbo.EstudiantePrograma WHERE programa = @progQa) e WHERE rn = 1;
SELECT @stUnaSesion = estudiante FROM (SELECT estudiante, ROW_NUMBER() OVER (ORDER BY estudiante) AS rn FROM dbo.EstudiantePrograma WHERE programa = @progQa) e WHERE rn = 2;
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @finished UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F');
DECLARE @absence UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @cerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID();
DECLARE @egTres UNIQUEIDENTIFIER = NEWID(), @egUna UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 700000 + ABS(CHECKSUM(NEWID()) % 99999);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @adminUser IS NULL OR @stTresSesiones IS NULL OR @stUnaSesion IS NULL
   OR @stTresSesiones = @stUnaSesion OR @active IS NULL OR @finished IS NULL OR @absence IS NULL OR @modoManual IS NULL OR @cerrada IS NULL
    THROW 52020, 'TEST FAILED: CULM001_C_HOR_10 fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Cierre C', @periodCode, DATEADD(DAY, -20, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA Masivo C', 30, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@egTres, @active, @stTresSesiones, @group), (@egUna, @active, @stUnaSesion, @group);
    DECLARE @firstDay DATE = DATEADD(DAY, -10, CAST(GETDATE() AS DATE));
    DECLARE @s TABLE (seq INT PRIMARY KEY, id UNIQUEIDENTIFIER);
    INSERT INTO @s VALUES (1, NEWID()), (2, NEWID()), (3, NEWID());
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT id, CONCAT(N'QA Cierre C ', seq), seq, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))), DATEADD(HOUR, 11, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))), N'UTC_V2'
    FROM @s;
    -- 3 tomas cerradas en cada sesion. PC (puntos de control): se abren en los minutos 0, 60 y 120 (antes todas en el inicio; con
    -- tramos solo contaria la ultima y la falta de la toma 1 de @egTres valdria 0 h). Asi la toma 1 SJC de @egTres da 1 h de falta
    -- por sesion ([0, 60] con un extremo SJC) y las 3 SJC de @egUna dan 3 h: los mismos 33 % de antes.
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, v.n, @modoManual, @cerrada, 0, @teacher, CAST(DATEADD(MINUTE, (v.n - 1) * 60, se.fechaHoraInicio) AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM @s s INNER JOIN dbo.Sesion se ON se.id = s.id CROSS JOIN (VALUES (1), (2), (3)) v(n);
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) SELECT NEWID(), @egTres, id FROM @s;
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) SELECT NEWID(), @egUna, id FROM @s WHERE seq = 1;
    -- @egTres: una ausencia (toma 1) en cada una de las 3 sesiones; @egUna: 3 ausencias (tomas 1..3) en la sesion 1
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, @absence, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM dbo.Asistencia a INNER JOIN dbo.Sesion se ON se.id = a.sesion INNER JOIN dbo.TomaAsistencia t ON t.sesion = a.sesion
    WHERE (a.estudianteGrupo = @egTres AND t.numero = 1) OR (a.estudianteGrupo = @egUna);
    IF (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia WHERE a.estudianteGrupo = @egUna) <> 3
        THROW 52021, 'TEST FAILED: CULM001_C_HOR_10 fixture: se esperaban 3 tomas ausentes en una sola sesion.', 1;
    -- Ambos quedan en 33 % por horas (3 h de 9 h): el cierre con el motor activo responde RCN_012 con 2 perdidas sin revision
    IF OBJECT_ID(N'tempdb..#h10c') IS NOT NULL DROP TABLE #h10c;
    CREATE TABLE #h10c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    INSERT INTO #h10c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF NOT EXISTS (SELECT 1 FROM #h10c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%RCN_012%')
       OR EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo WHERE eg.grupo = @group)
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estado = @active) <> 2
        THROW 52022, 'TEST FAILED: CULM001_C_HOR_10 con 2 perdidas por horas sin revision el cierre responde RCN_012 y no cambia estados ni crea revisiones.', 1;
    -- El motor crea las 2 revisiones; el titular las pasa a MANTENIDA; el cierre termina con ambas en F
    DECLARE @ev TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, ac INT, asup INT, are INT, rc INT, nov NVARCHAR(MAX));
    INSERT INTO @ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @group, @idCorrelacion = @corr, @idEstudianteGrupo = NULL;
    IF (SELECT rc FROM @ev) <> 2 THROW 52023, 'TEST FAILED: CULM001_C_HOR_10 el motor debe crear 2 revisiones.', 1;
    DECLARE @rid UNIQUEIDENTIFIER;
    DECLARE @dec TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idRev UNIQUEIDENTIFIER, ea NVARCHAR(20), en NVARCHAR(20), cd NVARCHAR(20), sc BIT,
        idGrupo UNIQUEIDENTIFIER, idEg UNIQUEIDENTIFIER, idEst UNIQUEIDENTIFIER, pct DECIMAL(5,2), plantilla VARCHAR(60), perfil NVARCHAR(20), esc BIT);
    DECLARE cur CURSOR LOCAL STATIC FORWARD_ONLY READ_ONLY FOR SELECT r.id FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo WHERE eg.grupo = @group;
    OPEN cur; FETCH NEXT FROM cur INTO @rid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO @dec EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rid, @codigoDecision = N'MANTENER', @motivo = N'Se mantiene al estudiante en el grupo', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
        FETCH NEXT FROM cur INTO @rid;
    END
    CLOSE cur; DEALLOCATE cur;
    IF (SELECT COUNT(*) FROM @dec WHERE estado = 1) <> 2 THROW 52025, 'TEST FAILED: CULM001_C_HOR_10 el titular debe poder mantener a ambos.', 1;
    DELETE FROM #h10c;
    INSERT INTO #h10c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF NOT EXISTS (SELECT 1 FROM #h10c WHERE estadoResultado = 1)
        THROW 52026, 'TEST FAILED: CULM001_C_HOR_10 con las revisiones decididas el cierre debe terminar.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estado = @finished) <> 2
        THROW 52027, 'TEST FAILED: CULM001_C_HOR_10 ambos estudiantes quedan en F (el cierre ya no cancela por conteo).', 1;
    PRINT 'TEST_PASS:CULM001_C_HOR_10_CIERRE_POR_HORAS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52024, 'TEST FAILED: CULM001_C_HOR_10 left transaction open.', 1;
GO

