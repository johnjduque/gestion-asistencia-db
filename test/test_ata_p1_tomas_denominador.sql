USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ATA P1 (docs/contracts/ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS.md, secciones A y B): edicion durante la sesion y denominador por horas del periodo.
--   ATA_P1_A00_MARGEN_DEFECTO_CERO         ASISTENCIA/MARGEN_RETARDO_MINUTOS vale 0 en la semilla.
--   ATA_P1_A01_EDITAR_TOMA_CERRADA         con la toma 2 abierta, la toma 1 cerrada se corrige (ya no hay TOM_012).
--   ATA_P1_A02_ESEDITABLE_EN_VENTANA       usp_consultar_tomas_sesion: ambas tomas editables hasta ventanaCierreUtc.
--   ATA_P1_A03_TRAS_VENTANA_SES_008        terminada la ventana ya nada se edita (SES_008) y esEditable = 0.
--   ATA_P1_A04_CIERRE_AL_FIN               con margen 0 el cierre automatico marca SJC apenas termina la sesion y no toca la sesion en curso.
--   ATA_P1_B01_DENOMINADOR_PERIODO         10 sesiones de 2 h y 1 vencida con falta completa = 10 % (no 100 %).
--   ATA_P1_B02_CANCELADA_NO_SUMA           una sesion cancelada sale del denominador.
--   ATA_P1_B03_SOLICITUD_NO_APROBADA       solicitudes pendientes y rechazadas no suman; la aprobada si.
--   ATA_P1_B04_ALERTAS_SOBRE_VISTA         usp_evaluar_alertas_inasistencia_grupo usa el % de la vista (10 % no crea alerta).
--   ATA_P1_B05_PROGRAMA_GRUPO_HORAS        uv_resumen_asistencia_estudiante_programa_grupo propaga horasPeriodo.
--   ATA_P1_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida. Requiere el helper test/fixtures/culm001_b2_toma_fixture.sql (test_suite.sql).
PRINT 'TEST START: test_ata_p1_tomas_denominador';

IF dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS') IS NULL
   OR dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS') <> 0
   OR COL_LENGTH(N'dbo.uv_cumplimiento_sesion_grupo', N'cuentaParaPeriodo') IS NULL
   OR COL_LENGTH(N'dbo.uv_resumen_asistencia_estudiante_grupo', N'horasPeriodo') IS NULL
   OR COL_LENGTH(N'dbo.uv_resumen_asistencia_estudiante_grupo', N'sesionesPeriodo') IS NULL
    THROW 59000, 'TEST FAILED ATA_P1_A00_MARGEN_DEFECTO_CERO: el margen de retardo debe valer 0 y las vistas deben exponer cuentaParaPeriodo, horasPeriodo y sesionesPeriodo.', 1;
PRINT 'TEST_PASS:ATA_P1_A00_MARGEN_DEFECTO_CERO';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estAbierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @estPendiente UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoSolicitudSesion WHERE esFinal = 0);
DECLARE @estRechazada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoSolicitudSesion WHERE esFinal = 1 AND esAprobada = 0);
DECLARE @estAprobada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoSolicitudSesion WHERE esAprobada = 1);
DECLARE @tipoCancelacion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @modoManual IS NULL OR @estAbierta IS NULL OR @estCerrada IS NULL
   OR @estPendiente IS NULL OR @estRechazada IS NULL OR @estAprobada IS NULL OR @tipoCancelacion IS NULL
    THROW 59001, 'TEST FAILED ATA_P1: faltan fixtures del seed (asignatura, institucion, estados, catalogos de toma y de solicitud de sesion).', 1;

CREATE TABLE #ataA (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
    ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
CREATE TABLE #ataC (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCierreUtc DATETIME2(0) NULL,
    totalAusentesMarcados INT NULL, totalFaltantes INT NULL, yaEstabaCerrada BIT NULL);
CREATE TABLE #ataL (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, totalRegistros INT NULL);
CREATE TABLE #ataV (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
CREATE TABLE #ataAl (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, alertasCreadas INT, alertasSuperadas INT,
    alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));
CREATE TABLE #ataS (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, numeroSesion INT, horasSesion DECIMAL(12,6), estaSesionCancelada BIT,
    motivoCancelacion NVARCHAR(500), ventanaAperturaUtc DATETIME2, ventanaCierreUtc DATETIME2, ventanaAbierta BIT, maximoTomas INT, totalTomasSesion INT,
    idToma UNIQUEIDENTIFIER, numero SMALLINT, idModo UNIQUEIDENTIFIER, codigoModo NVARCHAR(20), nombreModo NVARCHAR(50), usaCodigoQr BIT,
    marcaAusentesAlCerrar BIT, idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), nombreEstado NVARCHAR(50), estaAbierta BIT, esImplicita BIT,
    idDocenteApertura UNIQUEIDENTIFIER, fechaAperturaUtc DATETIME2(0), fechaCierreUtc DATETIME2(0), totalAusentesMarcados INT, horasToma DECIMAL(12,6),
    totalRegistros INT, totalPresentes INT, totalAusentes INT, totalExcusas INT, tieneQrActivo BIT,
    fechaPuntoControlUtc DATETIME2(7), ordenPuntoControl INT, minutosTramoAnterior INT, minutosTramoSiguiente INT, esEditable BIT, editableHastaUtc DATETIME2(7));

DECLARE @corr UNIQUEIDENTIFIER, @json NVARCHAR(MAX), @t1 UNIQUEIDENTIFIER, @t2 UNIQUEIDENTIFIER, @i INT;

BEGIN TRANSACTION;
BEGIN TRY
    -- Fixture: docente titular d (uD); estudiantes e1..e3 activos en el grupo g (tomas) y e1b en el grupo gB (denominador)
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #ataEst (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER, idEGb UNIQUEIDENTIFIER);
    INSERT INTO #ataEst (n, idUsuario, idEstudiante, idEG, idEGb) SELECT v.n, NEWID(), NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 987000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'Ata', N'Doc', N'P1', CONCAT(N'ata.d1.', @tag, N'@test.local'), 1, 1, N'HashBackend_ATA');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 988000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Estudiante', e.n), N'Ata', N'Est', N'P1',
           CONCAT(N'ata.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_ATA'
    FROM #ataEst e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #ataEst;
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID(), @gB UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'ATA periodo P1', 3960000 + ABS(CHECKSUM(NEWID()) % 30000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g,  @idAsig, @per, 959000 + ABS(CHECKSUM(NEWID()) % 4999), N'ATA Grupo tomas', 30, 0, 0, 0, @d),
           (@gB, @idAsig, @per, 964000 + ABS(CHECKSUM(NEWID()) % 4999), N'ATA Grupo denominador', 30, 0, 0, 0, @d);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT e.idEG, @estadoA, e.idEstudiante, @g FROM #ataEst e;
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT e.idEGb, @estadoA, e.idEstudiante, @gB FROM #ataEst e WHERE e.n = 1;
    DECLARE @e1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ataEst WHERE n = 1), @e2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ataEst WHERE n = 2);
    DECLARE @egB UNIQUEIDENTIFIER = (SELECT idEGb FROM #ataEst WHERE n = 1);

    -- Sesiones del grupo de tomas: en curso (ventana abierta), pasada (termino hace 10 min: con margen 0 la ventana ya cerro) y job (termino hace 1 min con toma abierta)
    DECLARE @sNow UNIQUEIDENTIFIER = NEWID(), @sPast UNIQUEIDENTIFIER = NEWID(), @sJob UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sNow,  N'ATA en curso', 1, CONCAT(N'AT1-', @tag), 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sPast, N'ATA pasada',   2, CONCAT(N'AT2-', @tag), 1, @g, DATEADD(MINUTE, -130, SYSUTCDATETIME()), DATEADD(MINUTE, -10, SYSUTCDATETIME()), N'UTC_V2'),
           (@sJob,  N'ATA job',      3, CONCAT(N'AT3-', @tag), 1, @g, DATEADD(MINUTE, -121, SYSUTCDATETIME()), DATEADD(MINUTE, -1, SYSUTCDATETIME()), N'UTC_V2');

    -- --------------------------------------------------------------------------------------------------------
    -- A01: con la toma 2 abierta, la toma 1 cerrada se corrige (el rechazo TOM_012 ya no existe)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ataA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @t1 = (SELECT idToma FROM #ataA WHERE estado = 1);
    TRUNCATE TABLE #ataA;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #ataL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    INSERT INTO #ataC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t1, @marcarAusentes = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @t1 IS NULL OR NOT EXISTS (SELECT 1 FROM #ataC WHERE estado = 1 AND idToma = @t1 AND totalAusentesMarcados = 2)
        THROW 59010, 'TEST FAILED ATA_P1_A01_EDITAR_TOMA_CERRADA: preparar la toma 1 cerrada con 2 ausentes marcados.', 1;
    TRUNCATE TABLE #ataL; TRUNCATE TABLE #ataC;
    INSERT INTO #ataA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @t2 = (SELECT idToma FROM #ataA WHERE estado = 1 AND numero = 2);
    TRUNCATE TABLE #ataA;
    IF @t2 IS NULL
        THROW 59011, 'TEST FAILED ATA_P1_A01_EDITAR_TOMA_CERRADA: no se pudo abrir la toma 2.', 1;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e2, N'","estado":"AN"}]');
    INSERT INTO #ataL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ataL WHERE estado = 1 AND (mt IS NULL OR mt NOT LIKE N'DBCODE=TOM[_]012|%') AND idToma = @t1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t1 AND eg.estudiante = @e2 AND v.codigoRazonCausa = N'AN')
        THROW 59012, 'TEST FAILED ATA_P1_A01_EDITAR_TOMA_CERRADA: con la toma 2 abierta, la toma 1 cerrada debe poder corregirse dentro de la ventana.', 1;
    TRUNCATE TABLE #ataL;
    PRINT 'TEST_PASS:ATA_P1_A01_EDITAR_TOMA_CERRADA';

    -- --------------------------------------------------------------------------------------------------------
    -- A02: ambas tomas editables hasta ventanaCierreUtc
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ataS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idSesion = @sNow;
    IF (SELECT COUNT(*) FROM #ataS) <> 2
       OR EXISTS (SELECT 1 FROM #ataS WHERE esEditable IS NULL OR esEditable <> 1 OR ventanaAbierta <> 1 OR editableHastaUtc IS NULL OR editableHastaUtc <> ventanaCierreUtc)
        THROW 59020, 'TEST FAILED ATA_P1_A02_ESEDITABLE_EN_VENTANA: mientras la ventana este abierta todas las tomas son editables hasta ventanaCierreUtc.', 1;
    TRUNCATE TABLE #ataS;
    PRINT 'TEST_PASS:ATA_P1_A02_ESEDITABLE_EN_VENTANA';

    -- --------------------------------------------------------------------------------------------------------
    -- A03: terminada la ventana, SES_008 sin escribir y esEditable = 0
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @tPast UNIQUEIDENTIFIER;
    EXEC #culm001_b2_crear_toma @idSesion = @sPast, @idToma = @tPast OUTPUT;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #ataL EXEC dbo.usp_registrar_asistencias_toma @idToma = @tPast, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ataL WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]008|%') OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma = @tPast)
        THROW 59030, 'TEST FAILED ATA_P1_A03_TRAS_VENTANA_SES_008: despues de ventanaCierreUtc la edicion responde SES_008 sin escribir.', 1;
    INSERT INTO #ataS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idSesion = @sPast;
    IF (SELECT COUNT(*) FROM #ataS) <> 1 OR NOT EXISTS (SELECT 1 FROM #ataS WHERE idToma = @tPast AND esEditable = 0 AND ventanaAbierta = 0 AND editableHastaUtc = ventanaCierreUtc)
        THROW 59031, 'TEST FAILED ATA_P1_A03_TRAS_VENTANA_SES_008: terminada la ventana esEditable debe ser 0.', 1;
    TRUNCATE TABLE #ataL; TRUNCATE TABLE #ataS;
    PRINT 'TEST_PASS:ATA_P1_A03_TRAS_VENTANA_SES_008';

    -- --------------------------------------------------------------------------------------------------------
    -- A04: con margen 0 el cierre automatico cierra la toma abierta de una sesion terminada hace 1 min (SJC) y no toca la sesion en curso
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @tJob UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    VALUES (@tJob, @sJob, 1, @modoManual, @estAbierta, 0, @d, DATEADD(MINUTE, -100, SYSUTCDATETIME()), NULL, NEWID());
    SET @corr = NEWID();
    INSERT INTO #ataV EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ataV WHERE idToma = @tJob AND idSesion = @sJob AND totalAusentesMarcados = 3)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.toma = @tJob AND rc.codigo = N'SJC') <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE id = @tJob AND fechaCierreUtc IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE id = @t2 AND fechaCierreUtc IS NULL)
        THROW 59040, 'TEST FAILED ATA_P1_A04_CIERRE_AL_FIN: con margen 0 el job cierra la toma de la sesion terminada marcando SJC y deja abierta la de la sesion en curso.', 1;
    TRUNCATE TABLE #ataV;
    PRINT 'TEST_PASS:ATA_P1_A04_CIERRE_AL_FIN';

    -- --------------------------------------------------------------------------------------------------------
    -- B01: 10 sesiones de 2 h en el grupo gB, 1 vencida con falta completa => 10 %
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @sB TABLE (n INT PRIMARY KEY, id UNIQUEIDENTIFIER);
    INSERT INTO @sB (n, id) SELECT v.n, NEWID() FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) v(n);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT b.id, CONCAT(N'ATA B', b.n), b.n, CONCAT(N'ATB', b.n, N'-', @tag), 1, @gB,
           IIF(b.n = 1, DATEADD(MINUTE, -180, SYSUTCDATETIME()), DATEADD(DAY, b.n, SYSUTCDATETIME())),
           IIF(b.n = 1, DATEADD(MINUTE, -60, SYSUTCDATETIME()), DATEADD(MINUTE, 120, DATEADD(DAY, b.n, SYSUTCDATETIME()))), N'UTC_V2'
    FROM @sB b;
    DECLARE @sB1 UNIQUEIDENTIFIER = (SELECT id FROM @sB WHERE n = 1), @tB1 UNIQUEIDENTIFIER = NEWID(), @aB1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT @tB1, s.id, 1, @modoManual, @estCerrada, 0, @d, CAST(s.fechaHoraInicio AS DATETIME2(0)), CAST(s.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM dbo.Sesion s WHERE s.id = @sB1;
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@aB1, @egB, @sB1);
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, @aB1, 0, rc.id, s.fechaHoraInicio, s.fechaHoraFin, @tB1, 0, SYSUTCDATETIME()
    FROM dbo.Sesion s CROSS JOIN dbo.RazonCausa rc WHERE s.id = @sB1 AND rc.codigo = N'SJC';
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                   WHERE r.idEstudianteGrupo = @egB AND r.sesionesPeriodo = 10 AND r.horasPeriodo = 20 AND r.horasDictadas = 2 AND r.horasFalta = 2
                     AND r.porcentajeInasistencia = 10.00 AND r.codigoPermanencia = N'REGULAR' AND r.sesionesEjecutadas = 1)
        THROW 59050, 'TEST FAILED ATA_P1_B01_DENOMINADOR_PERIODO: 2 h de falta sobre 20 h del periodo debe dar 10 % (REGULAR) con horasDictadas = 2.', 1;
    PRINT 'TEST_PASS:ATA_P1_B01_DENOMINADOR_PERIODO';

    -- B04 (misma base): el SP de alertas usa el % de la vista, asi que 10 % no cruza ningun umbral
    SET @corr = NEWID();
    INSERT INTO #ataAl EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @gB, @idCorrelacion = @corr, @idEstudianteGrupo = @egB;
    IF NOT EXISTS (SELECT 1 FROM #ataAl WHERE estado = 1 AND alertasCreadas = 0 AND revisionesCreadas = 0)
       OR EXISTS (SELECT 1 FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @egB)
        THROW 59053, 'TEST FAILED ATA_P1_B04_ALERTAS_SOBRE_VISTA: con 10 % de inasistencia sobre el periodo no debe crearse alerta (antes del cambio daba 100 % sobre lo dictado).', 1;
    TRUNCATE TABLE #ataAl;
    PRINT 'TEST_PASS:ATA_P1_B04_ALERTAS_SOBRE_VISTA';

    -- --------------------------------------------------------------------------------------------------------
    -- B02: una sesion cancelada sale del denominador (18 h)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, usuarioEjecutor, idCorrelacion)
    SELECT id, @tipoCancelacion, N'ATA cancelada', @uD, NEWID() FROM @sB WHERE n = 3;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                   WHERE r.idEstudianteGrupo = @egB AND r.sesionesPeriodo = 9 AND r.horasPeriodo = 18 AND r.porcentajeInasistencia = 11.11)
        THROW 59051, 'TEST FAILED ATA_P1_B02_CANCELADA_NO_SUMA: con una sesion cancelada el periodo suma 18 h y el porcentaje es 11.11.', 1;
    PRINT 'TEST_PASS:ATA_P1_B02_CANCELADA_NO_SUMA';

    -- --------------------------------------------------------------------------------------------------------
    -- B03: solicitud pendiente y rechazada no suman; la aprobada si (sesiones 4, 5 y 6) => 7 sesiones, 14 h
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, idCorrelacion)
    SELECT b.id, CASE b.n WHEN 4 THEN @estPendiente WHEN 5 THEN @estRechazada ELSE @estAprobada END, @uD, NEWID() FROM @sB b WHERE b.n IN (4, 5, 6);
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r
                   WHERE r.idEstudianteGrupo = @egB AND r.sesionesPeriodo = 7 AND r.horasPeriodo = 14 AND r.porcentajeInasistencia = 14.29)
       OR (SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo c WHERE c.idGrupo = @gB AND c.cuentaParaPeriodo = 0) <> 2
       OR (SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo c WHERE c.idGrupo = @gB) <> 9
        THROW 59052, 'TEST FAILED ATA_P1_B03_SOLICITUD_NO_APROBADA: pendiente y rechazada no cuentan, la aprobada si (7 sesiones, 14 h, 14.29 %).', 1;
    PRINT 'TEST_PASS:ATA_P1_B03_SOLICITUD_NO_APROBADA';

    -- --------------------------------------------------------------------------------------------------------
    -- B05: la vista por programa propaga horasPeriodo (columna presente y mismo valor que la vista base cuando la matricula tiene programa)
    -- --------------------------------------------------------------------------------------------------------
    IF COL_LENGTH(N'dbo.uv_resumen_asistencia_estudiante_programa_grupo', N'horasPeriodo') IS NULL
       OR EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_programa_grupo p
                  INNER JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = p.idEstudianteGrupo
                  WHERE p.horasPeriodo <> r.horasPeriodo OR p.porcentajeInasistencia <> r.porcentajeInasistencia)
        THROW 59054, 'TEST FAILED ATA_P1_B05_PROGRAMA_GRUPO_HORAS: la vista por programa debe exponer horasPeriodo con el mismo valor que la vista base.', 1;
    PRINT 'TEST_PASS:ATA_P1_B05_PROGRAMA_GRUPO_HORAS';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 59098, 'TEST FAILED ATA_P1_TRANCOUNT_ZERO: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:ATA_P1_TRANCOUNT_ZERO';
PRINT 'TEST END: test_ata_p1_tomas_denominador';
GO
