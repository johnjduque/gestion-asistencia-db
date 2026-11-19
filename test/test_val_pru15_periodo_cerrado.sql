USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- VAL-pendientes-john PRU-15 (decision del responsable 2026-11-18): regla de "periodo cerrado".
-- Un periodo queda CERRADO cuando usp_ejecutar_cierre_masivo_periodo lo cierra con exito (PeriodoAcademico.fechaCierreUtc). Desde ahi:
--   (a) tomas nuevas o cambios de tomas, lotes de asistencia y reclamos nuevos o cambios de reclamos de sus sesiones => PER_008, sin escribir;
--   (b) un segundo cierre del mismo periodo => PER_009, sin escribir ni auditar (antes era un exito idempotente con otra auditoria).
-- Fixture propio: periodo terminado ayer (estado CERRADO por fecha), grupo del docente con una matricula activa, sesion en curso, dos
-- sesiones pasadas dentro del plazo de reclamo, una toma abierta y un reclamo pendiente creados ANTES del cierre. Motor de alertas
-- apagado (no es lo que se prueba). Despues del cierre la matricula se devuelve a A para aislar la regla del periodo.
--   VAL_PRU15_00_TERMINADO_SIN_CIERRE_ADMITE   periodo terminado por fecha pero sin cierre: toma, lote y reclamo se admiten
--   VAL_PRU15_01_CIERRE_MARCA_PERIODO          el cierre exitoso marca fechaCierreUtc
--   VAL_PRU15_02_ABRIR_TOMA                    usp_abrir_toma_asistencia => PER_008, sin toma nueva
--   VAL_PRU15_03_LOTE_TOMA                     usp_registrar_asistencias_toma => PER_008, sin detalle
--   VAL_PRU15_04_LOTE_SESION                   usp_registrar_asistencias_sesion => PER_008, sin asistencia
--   VAL_PRU15_05_CERRAR_TOMA                   usp_cerrar_toma_asistencia => PER_008, la toma sigue abierta
--   VAL_PRU15_06_RECLAMO_NUEVO                 v3 (sesion) y v1 => PER_008, sin solicitud
--   VAL_PRU15_07_RESOLVER_RECLAMO              usp_resolver_solicitud_revision_asistencia => PER_008, sigue pendiente
--   VAL_PRU15_08_RETIRAR_RECLAMO               usp_retirar_solicitud_revision_asistencia => PER_008, sigue pendiente
--   VAL_PRU15_09_DOBLE_CIERRE                  segundo cierre => PER_009 con la fecha del primero, sin auditoria nueva ni cambios
--   VAL_PRU15_10_OTRO_PERIODO_NO_AFECTADO      el cierre de un periodo no bloquea las sesiones de otro
--   VAL_PRU15_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida.
-- ============================================================================
PRINT 'TEST START: test_val_pru15_periodo_cerrado (PRU-15, periodo cerrado)';
IF OBJECT_ID('tempdb..#pru15_expect') IS NOT NULL DROP PROCEDURE #pru15_expect;
GO
CREATE PROCEDURE #pru15_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: VAL_PRU15_', @label);
        THROW 52400, @mensaje, 1;
    END
END;
GO

DECLARE @zona NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @codInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codInscrita);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura ORDER BY id);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1 ORDER BY idUsuario);
DECLARE @teacher UNIQUEIDENTIFIER, @teacherUser UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @studentUser UNIQUEIDENTIFIER, @institution UNIQUEIDENTIFIER;

SELECT TOP 1 @teacher = g.docente, @student = eg.idEstudiante, @institution = pa.institucion
FROM dbo.uv_estudiante_grupo eg
INNER JOIN dbo.Grupo g ON g.id = eg.idGrupo
INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
WHERE eg.codigoEstadoEstudiante = @codInscrita
ORDER BY eg.idGrupo, eg.idEstudiante;
SELECT @teacherUser = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT @studentUser = usuario FROM dbo.Estudiante WHERE id = @student;

IF @estadoA IS NULL OR @assignment IS NULL OR @adminUser IS NULL OR @teacherUser IS NULL OR @studentUser IS NULL OR @institution IS NULL
    THROW 52401, 'TEST FAILED: VAL_PRU15 faltan datos sembrados (docente, estudiante inscrito, administrador, asignatura).', 1;

DECLARE @tag NVARCHAR(8) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 8);
DECLARE @per UNIQUEIDENTIFIER = NEWID(), @perAbierto UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID(), @gAbierto UNIQUEIDENTIFIER = NEWID();
DECLARE @eg UNIQUEIDENTIFIER = NEWID(), @egAbierto UNIQUEIDENTIFIER = NEWID();
DECLARE @nombrePer NVARCHAR(50) = CONCAT(N'QA-PRU15-', @tag);
DECLARE @sNow UNIQUEIDENTIFIER = NEWID(), @sRec UNIQUEIDENTIFIER = NEWID(), @sRec2 UNIQUEIDENTIFIER = NEWID(), @sAbierto UNIQUEIDENTIFIER = NEWID();
DECLARE @corr UNIQUEIDENTIFIER, @ok BIT, @json NVARCHAR(MAX), @toma UNIQUEIDENTIFIER, @solicitud UNIQUEIDENTIFIER;
DECLARE @antes INT, @despues INT, @audAntes INT, @mtLote NVARCHAR(4000), @estadoLote BIT, @fechaCierre DATETIME2(7), @textoPer008 NVARCHAR(4000), @descartado NVARCHAR(4000);

DROP TABLE IF EXISTS #p15r; DROP TABLE IF EXISTS #p15a; DROP TABLE IF EXISTS #p15c; DROP TABLE IF EXISTS #p15l; DROP TABLE IF EXISTS #p15s;
CREATE TABLE #p15r (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL);
CREATE TABLE #p15a (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
    ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL,
    idTomaCerradaAnterior UNIQUEIDENTIFIER NULL, numeroTomaCerradaAnterior SMALLINT NULL, totalAusentesMarcadosAnterior INT NULL);
CREATE TABLE #p15c (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCierreUtc DATETIME2(0) NULL,
    totalAusentesMarcados INT NULL, totalFaltantes INT NULL, yaEstabaCerrada BIT NULL);
CREATE TABLE #p15l (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, totalRegistros INT NULL);
CREATE TABLE #p15s (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL);

BEGIN TRANSACTION;
BEGIN TRY
    UPDATE dbo.CatalogoParametro SET valor = N'false' WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';

    -- Periodo terminado ayer (CERRADO por fecha, aun sin cierre masivo) y otro vigente; un grupo del mismo docente en cada uno
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (@per,        @institution, @nombrePer,                     3800000 + ABS(CHECKSUM(NEWID()) % 90000), DATEADD(DAY, -120, @hoy), DATEADD(DAY, -1, @hoy), YEAR(@hoy)),
        (@perAbierto, @institution, CONCAT(N'QA-PRU15-A-', @tag),   3900000 + ABS(CHECKSUM(NEWID()) % 90000), DATEADD(DAY, -30, @hoy),  DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente) VALUES
        (@g,        @assignment, @per,        948000 + ABS(CHECKSUM(NEWID()) % 999), N'QA PRU15 cerrado', 30, 0, 0, 0, @teacher),
        (@gAbierto, @assignment, @perAbierto, 947000 + ABS(CHECKSUM(NEWID()) % 999), N'QA PRU15 abierto', 30, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg, @estadoA, @student, @g), (@egAbierto, @estadoA, @student, @gAbierto);
    -- Sesion en curso (ventana abierta) y dos sesiones que terminaron hace 2 y 3 horas (plazo de reclamo vigente)
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal) VALUES
        (@sNow,     N'QA PRU15 en curso', 1, CONCAT(N'P15A', @tag), 1, @g,        DATEADD(MINUTE, -30, SYSUTCDATETIME()),  DATEADD(MINUTE, 90, SYSUTCDATETIME()),  N'UTC_V2'),
        (@sRec,     N'QA PRU15 reclamo',  2, CONCAT(N'P15B', @tag), 1, @g,        DATEADD(MINUTE, -240, SYSUTCDATETIME()), DATEADD(MINUTE, -120, SYSUTCDATETIME()), N'UTC_V2'),
        (@sRec2,    N'QA PRU15 reclamo2', 3, CONCAT(N'P15C', @tag), 1, @g,        DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2'),
        (@sAbierto, N'QA PRU15 abierto',  1, CONCAT(N'P15D', @tag), 1, @gAbierto, DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2');

    -- ---------------------------------------------------------------- 00: terminado por fecha pero sin cierre masivo: todo se admite
    SET @corr = NEWID();
    INSERT INTO #p15a EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @toma = (SELECT idToma FROM #p15a WHERE estado = 1);
    SET @json = CONCAT(N'[{"idEstudiante":"', @student, N'","estado":"AN"}]');
    INSERT INTO #p15l EXEC dbo.usp_registrar_asistencias_toma @idToma = @toma, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @corr = NEWID();
    INSERT INTO #p15s EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @student, @idSesion = @sRec, @categoria = N'CAL',
        @justificacion = N'QA PRU15 pendiente', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SET @solicitud = (SELECT idSolicitudRevision FROM #p15s WHERE estado = 1);
    SET @ok = IIF(@toma IS NOT NULL AND EXISTS (SELECT 1 FROM #p15l WHERE estado = 1) AND @solicitud IS NOT NULL
                  AND EXISTS (SELECT 1 FROM dbo.uv_periodo_academico WHERE id = @per AND estado = 'CERRADO'), 1, 0);
    EXEC #pru15_expect '00_TERMINADO_SIN_CIERRE_ADMITE', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_00_TERMINADO_SIN_CIERRE_ADMITE';

    -- ---------------------------------------------------------------- 01: el cierre exitoso marca el periodo
    TRUNCATE TABLE #p15r;
    SET @corr = NEWID();
    INSERT INTO #p15r EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @nombrePer, @idActor = N'QA_PRU15', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    EXEC sys.sp_executesql N'SELECT @f = fechaCierreUtc FROM dbo.PeriodoAcademico WHERE id = @p',
        N'@p UNIQUEIDENTIFIER, @f DATETIME2(7) OUTPUT', @p = @per, @f = @fechaCierre OUTPUT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15r WHERE estado = 1) AND @fechaCierre IS NOT NULL
                  AND @fechaCierre <= SYSUTCDATETIME() AND @fechaCierre > DATEADD(MINUTE, -5, SYSUTCDATETIME()), 1, 0);
    EXEC #pru15_expect '01_CIERRE_MARCA_PERIODO', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_01_CIERRE_MARCA_PERIODO';
    -- Aislar la regla: la matricula vuelve a A (el cierre la paso a F)
    UPDATE dbo.EstudianteGrupo SET estado = @estadoA WHERE id = @eg;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PER_008', @p_param1 = @nombrePer,
        @mensajeUsuarioResultado = @textoPer008 OUTPUT, @mensajeTecnicoResultado = @descartado OUTPUT;

    -- ---------------------------------------------------------------- 02: abrir una toma nueva
    TRUNCATE TABLE #p15a;
    SELECT @antes = COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow;
    SET @corr = NEWID();
    INSERT INTO #p15a EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15a WHERE estado = 0 AND idToma IS NULL AND mt LIKE N'DBCODE=PER[_]008|%' AND mu = @textoPer008)
                  AND (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sNow) = @antes AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '02_ABRIR_TOMA', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_02_ABRIR_TOMA';

    -- ---------------------------------------------------------------- 03: lote de la toma abierta
    TRUNCATE TABLE #p15l;
    SELECT @antes = COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @toma;
    SET @json = CONCAT(N'[{"idEstudiante":"', @student, N'","estado":"SJC"}]');
    SET @corr = NEWID();
    INSERT INTO #p15l EXEC dbo.usp_registrar_asistencias_toma @idToma = @toma, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15l WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]008|%')
                  AND (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @toma) = @antes
                  AND NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia d INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                                  WHERE d.toma = @toma AND rc.codigo = N'SJC') AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '03_LOTE_TOMA', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_03_LOTE_TOMA';

    -- ---------------------------------------------------------------- 04: lote de la sesion
    -- Este SP (congelado) revierte a su savepoint al rechazar, cosa que SQL Server no admite dentro de INSERT ... EXEC: se invoca con EXEC
    -- y su motivo se lee del validador de ventana que usa (el mismo paso 2.7 que rechaza el lote).
    SELECT @antes = COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @sNow;
    SET @corr = NEWID();
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sNow, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SELECT @despues = COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia WHERE a.sesion = @sNow;
    SELECT @descartado = N'', @mtLote = N'', @estadoLote = 1;
    EXEC dbo.usp_validar_sesion_ventana_registro_interno @idSesion = @sNow, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @descartado OUTPUT, @mensajeTecnicoResultado = @mtLote OUTPUT, @estadoResultado = @estadoLote OUTPUT;
    SET @ok = IIF(@estadoLote = 0 AND @mtLote LIKE N'DBCODE=PER[_]008|%' AND @antes = @despues AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '04_LOTE_SESION', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_04_LOTE_SESION';

    -- ---------------------------------------------------------------- 05: cerrar la toma abierta
    TRUNCATE TABLE #p15c;
    SET @corr = NEWID();
    INSERT INTO #p15c EXEC dbo.usp_cerrar_toma_asistencia @idToma = @toma, @marcarAusentes = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15c WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]008|%')
                  AND EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE id = @toma AND fechaCierreUtc IS NULL) AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '05_CERRAR_TOMA', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_05_CERRAR_TOMA';

    -- ---------------------------------------------------------------- 06: reclamo nuevo (v3 de la sesion y v1 legado)
    TRUNCATE TABLE #p15s;
    SELECT @antes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @corr = NEWID();
    INSERT INTO #p15s EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @student, @idSesion = @sRec2, @categoria = N'CAL',
        @justificacion = N'QA PRU15 tras el cierre', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    TRUNCATE TABLE #p15r;
    SET @corr = NEWID();
    INSERT INTO #p15r EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @student, @idSesion = @sRec2, @categoria = N'CAL',
        @justificacion = N'QA PRU15 v1 tras el cierre', @soporteNombre = NULL, @soporteUrl = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SELECT @despues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15s WHERE estado = 0 AND idSolicitudRevision IS NULL AND mt LIKE N'DBCODE=PER[_]008|%' AND mu = @textoPer008)
                  AND EXISTS (SELECT 1 FROM #p15r WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]008|%')
                  AND @antes = @despues AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '06_RECLAMO_NUEVO', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_06_RECLAMO_NUEVO';

    -- ---------------------------------------------------------------- 07: resolver el reclamo pendiente
    TRUNCATE TABLE #p15r;
    SET @corr = NEWID();
    INSERT INTO #p15r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @solicitud, @idDocente = @teacher, @accion = N'APROBADA',
        @respuestaDocente = N'QA PRU15', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15r WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]008|%')
                  AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Estado e ON e.id = r.estado
                              WHERE r.id = @solicitud AND e.codigo = 'P') AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '07_RESOLVER_RECLAMO', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_07_RESOLVER_RECLAMO';

    -- ---------------------------------------------------------------- 08: retirar el reclamo pendiente
    TRUNCATE TABLE #p15r;
    SET @corr = NEWID();
    INSERT INTO #p15r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @solicitud, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15r WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]008|%')
                  AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Estado e ON e.id = r.estado
                              WHERE r.id = @solicitud AND e.codigo = 'P') AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '08_RETIRAR_RECLAMO', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_08_RETIRAR_RECLAMO';

    -- ---------------------------------------------------------------- 09: segundo cierre del mismo periodo
    TRUNCATE TABLE #p15r;
    SELECT @audAntes = COUNT(*) FROM dbo.AuditoriaEvento WHERE action = 'CIERRE_MASIVO_PERIODO' AND resourceId = CAST(@per AS NVARCHAR(50));
    SET @corr = NEWID();
    INSERT INTO #p15r EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @nombrePer, @idActor = N'QA_PRU15', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    SET @ok = IIF((SELECT COUNT(*) FROM #p15r) = 1
                  AND EXISTS (SELECT 1 FROM #p15r WHERE estado = 0 AND mt LIKE N'DBCODE=PER[_]009|%'
                              AND mu LIKE N'%' + CONVERT(NVARCHAR(10), CAST((@fechaCierre AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE), 103) + N'%')
                  AND (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = 'CIERRE_MASIVO_PERIODO' AND resourceId = CAST(@per AS NVARCHAR(50))) = @audAntes
                  AND EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @eg AND estado = @estadoA)
                  AND @@TRANCOUNT = 1, 1, 0);
    EXEC #pru15_expect '09_DOBLE_CIERRE', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_09_DOBLE_CIERRE';

    -- ---------------------------------------------------------------- 10: otro periodo (vigente) no se afecta
    TRUNCATE TABLE #p15s;
    SET @corr = NEWID();
    INSERT INTO #p15s EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @student, @idSesion = @sAbierto, @categoria = N'CAL',
        @justificacion = N'QA PRU15 otro periodo', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p15s WHERE estado = 1 AND idSolicitudRevision IS NOT NULL), 1, 0);
    EXEC #pru15_expect '10_OTRO_PERIODO_NO_AFECTADO', @ok;
    PRINT 'TEST_PASS:VAL_PRU15_10_OTRO_PERIODO_NO_AFECTADO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #p15r; DROP TABLE IF EXISTS #p15a; DROP TABLE IF EXISTS #p15c; DROP TABLE IF EXISTS #p15l; DROP TABLE IF EXISTS #p15s;
    THROW 52402, @fallo, 1;
END CATCH
DROP TABLE IF EXISTS #p15r; DROP TABLE IF EXISTS #p15a; DROP TABLE IF EXISTS #p15c; DROP TABLE IF EXISTS #p15l; DROP TABLE IF EXISTS #p15s;
GO

IF @@TRANCOUNT = 0 AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE nombre LIKE N'QA-PRU15-%')
    PRINT 'TEST_PASS:VAL_PRU15_TRANCOUNT_ZERO';
ELSE
    THROW 52403, 'TEST FAILED: VAL_PRU15_TRANCOUNT_ZERO (transaccion abierta o datos de prueba sin revertir).', 1;
GO
DROP PROCEDURE #pru15_expect;
GO
