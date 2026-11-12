USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- PC BD-2 / BD-3 (docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B, TEST_PLAN.md): ciclo de vida de la toma y reclamo por toma.
--   PC_TOM_01..05  edicion hasta la siguiente toma (TOM_012), ultima hasta fin + margen (SES_008), cierre MANUAL marca SJC (SP y job),
--                  tope de 20 tomas (TOM_004), columnas nuevas de usp_consultar_tomas_sesion y usp_consultar_resumen_tomas_sesion.
--   PC_REC_01..10  radicacion v4 (toma obligatoria, TOM_001, REV_026, REV_027), resolucion con resultado PRESENTE (AN) o JUSTIFICADA
--                  (EX) solo en la toma, legado (REV_029 y SES-04), idempotencia (REV_002) y REV_028, retiro y nueva radicacion,
--                  uv_asistencia_toma_estudiante y consultas de reclamos (estudiante y detalle docente).
--   PC_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida. Requiere el helper test/fixtures/culm001_b2_toma_fixture.sql (test_suite.sql).
PRINT 'TEST START: test_pc_puntos_control (PC BD-2 / BD-3)';

IF OBJECT_ID(N'dbo.uv_asistencia_toma_estudiante', N'V') IS NULL OR OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v4', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_resumen_tomas_sesion', N'P') IS NULL
   OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NULL OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'razonCausaResolucion') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.SolicitudRevisionAsistencia') AND name = N'IX_SolicitudRevisionAsistencia_Asistencia_Toma')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SolicitudRevisionAsistencia_TomaAsistencia')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SolicitudRevisionAsistencia_RazonCausaResolucion')
   OR EXISTS (SELECT 1 FROM (VALUES ('TOM_012'), ('REV_026'), ('REV_027'), ('REV_028'), ('REV_029')) c(codigo)
              WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
                 OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
   OR dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION') <> 20
   OR NOT EXISTS (SELECT 1 FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0 AND marcaAusentesAlCerrar = 1)
    THROW 58100, 'TEST FAILED PC_TOM_00: faltan objetos, columnas, mensajes o semillas de PC (tope 20, MANUAL marca ausentes).', 1;
PRINT 'TEST_PASS:PC_TOM_00_OBJETOS_Y_SEMILLAS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estAbierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @modoManual IS NULL OR @estAbierta IS NULL OR @estCerrada IS NULL
    THROW 58101, 'TEST FAILED PC_TOM: faltan fixtures del seed (asignatura, institucion, estados, catalogos de toma).', 1;

CREATE TABLE #ptcA (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
    ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
CREATE TABLE #ptcC (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCierreUtc DATETIME2(0) NULL,
    totalAusentesMarcados INT NULL, totalFaltantes INT NULL, yaEstabaCerrada BIT NULL);
CREATE TABLE #ptcL (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, totalRegistros INT NULL);
CREATE TABLE #ptcV (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
CREATE TABLE #ptcK (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL);
CREATE TABLE #ptc3 (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL);
CREATE TABLE #ptc4 (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL, idToma UNIQUEIDENTIFIER NULL);
CREATE TABLE #ptcS (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, numeroSesion INT, horasSesion DECIMAL(12,6), estaSesionCancelada BIT,
    motivoCancelacion NVARCHAR(500), ventanaAperturaUtc DATETIME2, ventanaCierreUtc DATETIME2, ventanaAbierta BIT, maximoTomas INT, totalTomasSesion INT,
    idToma UNIQUEIDENTIFIER, numero SMALLINT, idModo UNIQUEIDENTIFIER, codigoModo NVARCHAR(20), nombreModo NVARCHAR(50), usaCodigoQr BIT,
    marcaAusentesAlCerrar BIT, idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), nombreEstado NVARCHAR(50), estaAbierta BIT, esImplicita BIT,
    idDocenteApertura UNIQUEIDENTIFIER, fechaAperturaUtc DATETIME2(0), fechaCierreUtc DATETIME2(0), totalAusentesMarcados INT, horasToma DECIMAL(12,6),
    totalRegistros INT, totalPresentes INT, totalAusentes INT, totalExcusas INT, tieneQrActivo BIT,
    fechaPuntoControlUtc DATETIME2(7), ordenPuntoControl INT, minutosTramoAnterior INT, minutosTramoSiguiente INT, esEditable BIT, editableHastaUtc DATETIME2(7));
CREATE TABLE #ptcRes (idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), minutosSesion INT, minutosAsistidos INT, minutosFalta INT,
    minutosExcusa INT, minutosSinRegistro INT, codigoEstadoSesionEstudiante NVARCHAR(20), tomasAusentes INT);
CREATE TABLE #ptcE (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT,
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), soportesJson NVARCHAR(MAX),
    idToma UNIQUEIDENTIFIER, numeroToma SMALLINT, fechaPuntoControlUtc DATETIME2(7), codigoResultadoAprobacion NVARCHAR(10));
CREATE TABLE #ptcD (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
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

DECLARE @corr UNIQUEIDENTIFIER, @json NVARCHAR(MAX), @t1 UNIQUEIDENTIFIER, @t2 UNIQUEIDENTIFIER, @n INT, @msg NVARCHAR(4000), @ok INT;
DECLARE @sol UNIQUEIDENTIFIER, @sol2 UNIQUEIDENTIFIER, @auditoria INT;

BEGIN TRANSACTION;
BEGIN TRY
    -- Fixture: docente titular d (uD) y ajeno (uD2); estudiantes e1..e5 activos; grupo g en un periodo vigente
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #ptcEst (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER, idAsistencia UNIQUEIDENTIFIER);
    INSERT INTO #ptcEst (n, idUsuario, idEstudiante, idEG, idAsistencia) SELECT v.n, NEWID(), NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4),(5)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 977000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'Puntos', N'Doc', N'PC', CONCAT(N'pc.d1.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC'),
           (@uD2, @tipoCC, 978000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Ajeno', N'Puntos', N'Doc', N'PC', CONCAT(N'pc.d2.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 979000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Estudiante', e.n), N'Puntos', N'Est', N'PC',
           CONCAT(N'pc.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC'
    FROM #ptcEst e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD), (@d2, @uD2);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #ptcEst;
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'PC periodo puntos de control', 3950000 + ABS(CHECKSUM(NEWID()) % 40000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 949000 + ABS(CHECKSUM(NEWID()) % 9999), N'PC Grupo puntos de control', 30, 0, 0, 0, @d);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT e.idEG, @estadoA, e.idEstudiante, @g FROM #ptcEst e;
    DECLARE @e1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ptcEst WHERE n = 1), @e2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ptcEst WHERE n = 2);
    DECLARE @e3 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ptcEst WHERE n = 3), @e5 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #ptcEst WHERE n = 5);
    DECLARE @uE1 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ptcEst WHERE n = 1), @uE2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ptcEst WHERE n = 2);
    DECLARE @uE3 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ptcEst WHERE n = 3), @uE5 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ptcEst WHERE n = 5);

    -- Sesiones: en curso (ventana abierta), tope, dentro del margen (fin hace 10 min), pasada (ventana vencida), job (vencida con una
    -- toma MANUAL abierta) y la del reclamo (de 2 h, termino hace ~23 h: plazo HU026B vigente), en minutos enteros
    DECLARE @sNow UNIQUEIDENTIFIER = NEWID(), @sTope UNIQUEIDENTIFIER = NEWID(), @sMargen UNIQUEIDENTIFIER = NEWID(), @sPast UNIQUEIDENTIFIER = NEWID();
    DECLARE @sJob UNIQUEIDENTIFIER = NEWID(), @sRec UNIQUEIDENTIFIER = NEWID();
    DECLARE @baseRec DATETIME2(7) = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('2000-01-01' AS DATETIME2(7)), SYSUTCDATETIME()) - 1500, CAST('2000-01-01' AS DATETIME2(7)));
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sNow,    N'PC en curso',  1, CONCAT(N'PC1-', @tag), 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sTope,   N'PC tope',      2, CONCAT(N'PC2-', @tag), 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2'),
           (@sMargen, N'PC margen',    3, CONCAT(N'PC3-', @tag), 1, @g, DATEADD(MINUTE, -130, SYSUTCDATETIME()), DATEADD(MINUTE, -10, SYSUTCDATETIME()), N'UTC_V2'),
           (@sPast,   N'PC pasada',    4, CONCAT(N'PC4-', @tag), 1, @g, DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2'),
           (@sJob,    N'PC job',       5, CONCAT(N'PC5-', @tag), 1, @g, DATEADD(MINUTE, -300, SYSUTCDATETIME()), DATEADD(MINUTE, -180, SYSUTCDATETIME()), N'UTC_V2'),
           (@sRec,    N'PC reclamo',   6, CONCAT(N'PC6-', @tag), 1, @g, @baseRec, DATEADD(MINUTE, 120, @baseRec), N'UTC_V2');

    -- Sesion del reclamo: tomas MANUAL cerradas en los minutos 0, 40 y 100. Marcas: e1 AN/SJC/AN (PC_CAL_03), e2 SJC/SJC/SJC,
    -- e3 AN/EX/(sin detalle), e4 sin cabecera, e5 AN/AN/SJC
    DECLARE @r1 UNIQUEIDENTIFIER = NEWID(), @r2 UNIQUEIDENTIFIER = NEWID(), @r3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    VALUES (@r1, @sRec, 1, @modoManual, @estCerrada, 0, @d, @baseRec, DATEADD(MINUTE, 10, @baseRec), NEWID()),
           (@r2, @sRec, 2, @modoManual, @estCerrada, 0, @d, DATEADD(MINUTE, 40, @baseRec), DATEADD(MINUTE, 50, @baseRec), NEWID()),
           (@r3, @sRec, 3, @modoManual, @estCerrada, 0, @d, DATEADD(MINUTE, 100, @baseRec), DATEADD(MINUTE, 110, @baseRec), NEWID());
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) SELECT e.idAsistencia, e.idEG, @sRec FROM #ptcEst e WHERE e.n <> 4;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, e.idAsistencia, IIF(m.codigo = N'AN', 1, 0), rc.id,
           @baseRec, DATEADD(MINUTE, 120, @baseRec), m.toma, 0, SYSUTCDATETIME()
    FROM (VALUES (1, @r1, N'AN'), (1, @r2, N'SJC'), (1, @r3, N'AN'),
                 (2, @r1, N'SJC'), (2, @r2, N'SJC'), (2, @r3, N'SJC'),
                 (3, @r1, N'AN'), (3, @r2, N'EX'),
                 (5, @r1, N'AN'), (5, @r2, N'AN'), (5, @r3, N'SJC')) m(n, toma, codigo)
    INNER JOIN #ptcEst e ON e.n = m.n
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = m.codigo;

    -- --------------------------------------------------------------------------------------------------------
    -- PC_TOM_01: la toma 1 cerrada se corrige mientras no se abra la 2; al abrir la 2, corregir la 1 da TOM_012 sin escribir.
    -- PC_TOM_03 (parte 1): cerrar una toma MANUAL con @marcarAusentes NULL marca SJC a los activos sin registro.
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptcA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @t1 = (SELECT idToma FROM #ptcA WHERE estado = 1);
    TRUNCATE TABLE #ptcA;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    INSERT INTO #ptcC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t1, @marcarAusentes = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @t1 IS NULL OR NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM #ptcC WHERE estado = 1 AND idToma = @t1 AND totalAusentesMarcados = 4)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
           WHERE da.toma = @t1 AND rc.codigo = N'SJC' AND da.asistio = 0) <> 4
        THROW 58110, 'TEST FAILED PC_TOM_03_CIERRE_MANUAL_MARCA: cerrar una toma MANUAL con @marcarAusentes NULL debe marcar SJC a los 4 activos sin registro.', 1;
    TRUNCATE TABLE #ptcL; TRUNCATE TABLE #ptcC;
    -- correccion de la toma 1 cerrada (es la ultima): permitida
    SET @json = CONCAT(N'[{"idEstudiante":"', @e2, N'","estado":"AN"}]');
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 1 AND mt LIKE N'DBCODE=TOM[_]010|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t1 AND eg.estudiante = @e2 AND v.codigoRazonCausa = N'AN')
        THROW 58111, 'TEST FAILED PC_TOM_01_EDICION_HASTA_SIGUIENTE: la toma cerrada sin toma posterior debe poder corregirse.', 1;
    TRUNCATE TABLE #ptcL;
    INSERT INTO #ptcA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sNow, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @t2 = (SELECT idToma FROM #ptcA WHERE estado = 1 AND numero = 2);
    TRUNCATE TABLE #ptcA;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e3, N'","estado":"AN"}]');
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @t2 IS NULL
       OR NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]012|%' AND mu LIKE N'%toma 1 %toma 2%'
                      AND idToma IS NULL AND totalRegistros IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia_v2 v INNER JOIN dbo.EstudianteGrupo eg ON eg.id = v.idEstudianteGrupo
                      WHERE v.idToma = @t1 AND eg.estudiante = @e3 AND v.codigoRazonCausa = N'SJC')
        THROW 58112, 'TEST FAILED PC_TOM_01_EDICION_HASTA_SIGUIENTE: con la toma 2 abierta, corregir la toma 1 debe responder TOM_012 sin escribir.', 1;
    TRUNCATE TABLE #ptcL;
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t2, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 1)
        THROW 58113, 'TEST FAILED PC_TOM_01_EDICION_HASTA_SIGUIENTE: la toma abierta (la 2) debe admitir registros.', 1;
    TRUNCATE TABLE #ptcL;
    PRINT 'TEST_PASS:PC_TOM_01_EDICION_HASTA_SIGUIENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_TOM_05: usp_consultar_tomas_sesion (columnas nuevas) y usp_consultar_resumen_tomas_sesion (minutos, RBAC, titularidad)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ptcS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idSesion = @sNow;
    IF (SELECT COUNT(*) FROM #ptcS) <> 2
       OR NOT EXISTS (SELECT 1 FROM #ptcS s INNER JOIN dbo.TomaAsistencia t2 ON t2.id = @t2
                      WHERE s.idToma = @t1 AND s.ordenPuntoControl = 1 AND s.esEditable = 0 AND s.editableHastaUtc = t2.fechaAperturaUtc
                        AND s.fechaPuntoControlUtc IS NOT NULL AND s.maximoTomas = 20)
       OR NOT EXISTS (SELECT 1 FROM #ptcS WHERE idToma = @t2 AND ordenPuntoControl = 2 AND esEditable = 1 AND editableHastaUtc = ventanaCierreUtc
                        AND minutosTramoSiguiente >= 0)
        THROW 58114, 'TEST FAILED PC_TOM_05_CONSULTAS: usp_consultar_tomas_sesion debe exponer punto de control, esEditable y editableHastaUtc.', 1;
    TRUNCATE TABLE #ptcS;
    INSERT INTO #ptcS EXEC dbo.usp_consultar_tomas_sesion @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idSesion = @sTope;
    IF (SELECT COUNT(*) FROM #ptcS) <> 1 OR EXISTS (SELECT 1 FROM #ptcS WHERE idToma IS NOT NULL OR esEditable IS NOT NULL OR editableHastaUtc IS NOT NULL)
        THROW 58115, 'TEST FAILED PC_TOM_05_CONSULTAS: una sesion sin tomas devuelve las columnas nuevas en NULL.', 1;
    TRUNCATE TABLE #ptcS;
    INSERT INTO #ptcRes EXEC dbo.usp_consultar_resumen_tomas_sesion @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idSesion = @sRec;
    IF (SELECT COUNT(*) FROM #ptcRes) <> 5
       OR NOT EXISTS (SELECT 1 FROM #ptcRes WHERE idEstudiante = @e1 AND minutosSesion = 120 AND minutosAsistidos = 20 AND minutosFalta = 100 AND minutosExcusa = 0
                        AND minutosSinRegistro = 0 AND codigoEstadoSesionEstudiante = N'PARCIAL' AND tomasAusentes = 1)
       OR NOT EXISTS (SELECT 1 FROM #ptcRes WHERE idEstudiante = @e2 AND minutosAsistidos = 0 AND minutosFalta = 120 AND codigoEstadoSesionEstudiante = N'AUSENTE' AND tomasAusentes = 3)
       OR NOT EXISTS (SELECT 1 FROM #ptcRes WHERE idEstudiante = @e3 AND minutosAsistidos = 0 AND minutosFalta = 0 AND minutosExcusa = 40 AND minutosSinRegistro = 80
                        AND codigoEstadoSesionEstudiante = N'JUSTIFICADA' AND tomasAusentes = 0)
       OR NOT EXISTS (SELECT 1 FROM #ptcRes r INNER JOIN #ptcEst e ON e.idEstudiante = r.idEstudiante
                      WHERE e.n = 4 AND r.minutosSesion = 120 AND r.minutosAsistidos = 0 AND r.minutosSinRegistro = 120 AND r.codigoEstadoSesionEstudiante = N'NO_DISPONIBLE')
        THROW 58116, 'TEST FAILED PC_TOM_05_CONSULTAS: usp_consultar_resumen_tomas_sesion debe dar los minutos por tramos de cada matricula activa.', 1;
    TRUNCATE TABLE #ptcRes;
    SET @ok = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_resumen_tomas_sesion @idUsuarioEjecutor = @uD2, @idCorrelacion = @corr, @idSesion = @sRec;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=SEC[_]002|%' SET @ok += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_resumen_tomas_sesion @idUsuarioEjecutor = @uE1, @idCorrelacion = @corr, @idSesion = @sRec;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=SEC[_]001|%' SET @ok += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_resumen_tomas_sesion @idUsuarioEjecutor = NULL, @idCorrelacion = @corr, @idSesion = @sRec;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF ERROR_NUMBER() = 51000 AND @msg LIKE N'DBCODE=GEN[_]002|%' SET @ok += 1;
    END CATCH;
    IF @ok <> 3 OR XACT_STATE() <> 1
        THROW 58117, 'TEST FAILED PC_TOM_05_CONSULTAS: el resumen debe lanzar 51000 con SEC_002 (no titular), SEC_001 (no docente) y GEN_002 (sin ejecutor).', 1;
    PRINT 'TEST_PASS:PC_TOM_05_CONSULTAS';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_TOM_02: la ultima toma se corrige hasta fin + margen; despues, SES_008
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptcA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sMargen, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @t1 = (SELECT idToma FROM #ptcA WHERE estado = 1);
    TRUNCATE TABLE #ptcA;
    INSERT INTO #ptcC EXEC dbo.usp_cerrar_toma_asistencia @idToma = @t1, @marcarAusentes = 0, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @json = CONCAT(N'[{"idEstudiante":"', @e1, N'","estado":"AN"}]');
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @t1, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @t1 IS NULL OR NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 1)
        THROW 58120, 'TEST FAILED PC_TOM_02_ULTIMA_HASTA_MARGEN: la ultima toma cerrada debe corregirse dentro del margen posterior al fin.', 1;
    TRUNCATE TABLE #ptcL; TRUNCATE TABLE #ptcC;
    DECLARE @tPast UNIQUEIDENTIFIER;
    EXEC #culm001_b2_crear_toma @idSesion = @sPast, @idToma = @tPast OUTPUT;
    INSERT INTO #ptcL EXEC dbo.usp_registrar_asistencias_toma @idToma = @tPast, @asistenciaJSON = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcL WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]008|%') OR EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma = @tPast)
        THROW 58121, 'TEST FAILED PC_TOM_02_ULTIMA_HASTA_MARGEN: despues de fin + margen la ultima toma responde SES_008 sin escribir.', 1;
    TRUNCATE TABLE #ptcL;
    PRINT 'TEST_PASS:PC_TOM_02_ULTIMA_HASTA_MARGEN';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_TOM_03 (parte 2): el cierre automatico de una toma MANUAL vencida tambien marca SJC
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @tJob UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    VALUES (@tJob, @sJob, 1, @modoManual, @estAbierta, 0, @d, DATEADD(MINUTE, -290, SYSUTCDATETIME()), NULL, NEWID());
    SET @corr = NEWID();
    INSERT INTO #ptcV EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ptcV WHERE idToma = @tJob AND idSesion = @sJob AND totalAusentesMarcados = 5)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa WHERE da.toma = @tJob AND rc.codigo = N'SJC') <> 5
        THROW 58130, 'TEST FAILED PC_TOM_03_CIERRE_MANUAL_MARCA: el cierre automatico de una toma MANUAL vencida debe marcar SJC a los activos.', 1;
    TRUNCATE TABLE #ptcV;
    PRINT 'TEST_PASS:PC_TOM_03_CIERRE_MANUAL_MARCA';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_TOM_04: con 20 tomas la 21 responde TOM_004 (tope parametrizado)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), @sTope, v.n, @modoManual, @estCerrada, 0, @d, DATEADD(SECOND, v.n - 40, SYSUTCDATETIME()), DATEADD(SECOND, v.n - 39, SYSUTCDATETIME()), NEWID()
    FROM (SELECT TOP 20 n = CAST(ROW_NUMBER() OVER (ORDER BY o.object_id) AS INT) FROM sys.objects o) v;
    SET @corr = NEWID();
    INSERT INTO #ptcA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sTope, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcA WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]004|%' AND mu LIKE N'%20%')
       OR (SELECT COUNT(*) FROM dbo.TomaAsistencia WHERE sesion = @sTope) <> 20
        THROW 58140, 'TEST FAILED PC_TOM_04_TOPE_20: con 20 tomas la 21 debe responder TOM_004 sin crearla.', 1;
    DELETE FROM dbo.TomaAsistencia WHERE sesion = @sTope AND numero = 20;
    TRUNCATE TABLE #ptcA;
    INSERT INTO #ptcA EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sTope, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcA WHERE estado = 1 AND numero = 20)
        THROW 58141, 'TEST FAILED PC_TOM_04_TOPE_20: con 19 tomas se debe poder abrir la 20.', 1;
    TRUNCATE TABLE #ptcA;
    PRINT 'TEST_PASS:PC_TOM_04_TOPE_20';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_01: v4 radica el reclamo de una toma con SJC (toma obligatoria: GEN_002); la toma queda no reclamable
    -- --------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e1 AND idToma = @r2 AND numeroToma = 2 AND codigoRazonCausa = N'SJC'
                     AND codigoEstadoTomaEstudiante = N'AUSENTE' AND esReclamable = 1 AND idSolicitudRevision IS NULL
                     AND fechaPuntoControlUtc = DATEADD(MINUTE, 40, @baseRec) AND minutosTramoAnterior = 40 AND minutosTramoSiguiente = 60)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e1 AND idToma = @r1 AND codigoEstadoTomaEstudiante = N'PRESENTE' AND esReclamable = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e3 AND idToma = @r3 AND codigoRazonCausa IS NULL
                        AND codigoEstadoTomaEstudiante = N'SIN_REGISTRO' AND esReclamable = 0)
       OR (SELECT COUNT(*) FROM dbo.uv_asistencia_toma_estudiante WHERE idSesion = @sRec) <> 12
        THROW 58150, 'TEST FAILED PC_REC_01: uv_asistencia_toma_estudiante debe dar una fila por cabecera y toma con su estado y si es reclamable.', 1;
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e1, @idSesion = @sRec, @idToma = @r2, @categoria = N'CAL',
        @justificacion = N'Estuve en clase, la toma 2 no me registro', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    SET @sol = (SELECT idSolicitudRevision FROM #ptc4 WHERE estado = 1);
    IF @sol IS NULL OR NOT EXISTS (SELECT 1 FROM #ptc4 WHERE estado = 1 AND idToma = @r2 AND totalSoportes = 0 AND idCorrelacion = @corr)
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia s INNER JOIN #ptcEst e ON e.idAsistencia = s.asistencia
                      WHERE s.id = @sol AND e.n = 1 AND s.toma = @r2 AND s.razonCausaResolucion IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia WHERE id = @sol AND idToma = @r2 AND numeroToma = 2 AND codigoResultadoAprobacion IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e1 AND idToma = @r2 AND esReclamable = 0
                        AND idSolicitudRevision = @sol AND codigoEstadoSolicitud = N'P')
        THROW 58151, 'TEST FAILED PC_REC_01: v4 debe radicar el reclamo de la toma con SJC y guardar la toma.', 1;
    TRUNCATE TABLE #ptc4;
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e1, @idSesion = @sRec, @idToma = NULL, @categoria = N'CAL',
        @justificacion = N'Sin toma', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #ptc4 WHERE estado = 0 AND mt LIKE N'DBCODE=GEN[_]002|%' AND idSolicitudRevision IS NULL AND idToma IS NULL)
        THROW 58152, 'TEST FAILED PC_REC_01: v4 sin toma debe responder GEN_002.', 1;
    TRUNCATE TABLE #ptc4;
    PRINT 'TEST_PASS:PC_REC_01_RADICAR_V4';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_02 / 03 / 04: REV_026 (toma con AN, EX o sin detalle), REV_027 (duplicado no retirado), TOM_001 (toma de otra sesion)
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @antes INT = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia);
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e1, @idSesion = @sRec, @idToma = @r1, @categoria = N'CAL',
        @justificacion = N'AN', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e3, @idSesion = @sRec, @idToma = @r2, @categoria = N'CAL',
        @justificacion = N'EX', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE3;
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e3, @idSesion = @sRec, @idToma = @r3, @categoria = N'CAL',
        @justificacion = N'Sin detalle', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE3;
    IF (SELECT COUNT(*) FROM #ptc4 WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]026|%' AND idSolicitudRevision IS NULL) <> 3
       OR (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia) <> @antes
        THROW 58160, 'TEST FAILED PC_REC_02: reclamar una toma con AN, EX o sin detalle debe responder REV_026 sin escribir.', 1;
    TRUNCATE TABLE #ptc4;
    PRINT 'TEST_PASS:PC_REC_02_TOMA_SIN_AUSENCIA';
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e1, @idSesion = @sRec, @idToma = @r2, @categoria = N'CAL',
        @justificacion = N'Duplicado', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #ptc4 WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]027|%') OR (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia) <> @antes
        THROW 58161, 'TEST FAILED PC_REC_03: un segundo reclamo no retirado de la misma toma debe responder REV_027 sin escribir.', 1;
    TRUNCATE TABLE #ptc4;
    PRINT 'TEST_PASS:PC_REC_03_DUPLICADO';
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e1, @idSesion = @sRec, @idToma = @t2, @categoria = N'CAL',
        @justificacion = N'Toma de otra sesion', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #ptc4 WHERE estado = 0 AND mt LIKE N'DBCODE=TOM[_]001|%') OR (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia) <> @antes
        THROW 58162, 'TEST FAILED PC_REC_04: reclamar una toma de otra sesion debe responder TOM_001 sin escribir.', 1;
    TRUNCATE TABLE #ptc4;
    PRINT 'TEST_PASS:PC_REC_04_TOMA_DE_OTRA_SESION';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_05: aprobacion "si estuvo presente" (AN): la toma pasa a AN y los minutos se recalculan (PC_CAL_13)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Verificado en clase', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD, @codigoResultadoAprobacion = N'AN';
    IF NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN #ptcEst e ON e.idAsistencia = da.asistencia
                      WHERE e.n = 1 AND da.toma = @r2 AND rc.codigo = N'AN' AND da.asistio = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #ptcEst e ON e.idAsistencia = h.idAsistencia
                      WHERE e.n = 1 AND h.minutosAsistidos = 120 AND h.minutosFalta = 0 AND h.codigoEstadoSesionEstudiante = N'PRESENTE')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia WHERE id = @sol AND codigoResultadoAprobacion = N'AN')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e1 AND idToma = @r2 AND codigoEstadoSolicitud = N'A'
                        AND codigoResultadoAprobacion = N'AN' AND codigoEstadoTomaEstudiante = N'PRESENTE' AND esReclamable = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@sol AS NVARCHAR(120)) AND correlationId = @corr
                        AND JSON_VALUE(metadata, '$.resultadoAprobacion') = N'AN' AND JSON_VALUE(metadata, '$.idToma') = CAST(@r2 AS NVARCHAR(36)))
        THROW 58170, 'TEST FAILED PC_REC_05: aprobar como PRESENTE debe dejar la toma en AN (asistio = 1), recalcular minutos y auditar el resultado.', 1;
    TRUNCATE TABLE #ptcK;
    PRINT 'TEST_PASS:PC_REC_05_APROBADA_PRESENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_06: aprobacion "ausencia justificada" (resultado NULL = EX): solo esa toma pasa a EX; los otros SJC quedan intactos
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e2, @idSesion = @sRec, @idToma = @r1, @categoria = N'CAL',
        @justificacion = N'Cita medica', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE2;
    SET @sol2 = (SELECT idSolicitudRevision FROM #ptc4 WHERE estado = 1);
    TRUNCATE TABLE #ptc4;
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol2, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Justificada', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @sol2 IS NULL OR NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR (SELECT STRING_AGG(CONCAT(t.numero, N':', rc.codigo, N':', CAST(da.asistio AS INT)), N',') WITHIN GROUP (ORDER BY t.numero)
           FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
           INNER JOIN #ptcEst e ON e.idAsistencia = da.asistencia WHERE e.n = 2) <> N'1:EX:0,2:SJC:0,3:SJC:0'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia WHERE id = @sol2 AND codigoResultadoAprobacion = N'EX')
        THROW 58180, 'TEST FAILED PC_REC_06: aprobar como JUSTIFICADA debe pasar a EX solo la toma reclamada.', 1;
    TRUNCATE TABLE #ptcK;
    PRINT 'TEST_PASS:PC_REC_06_APROBADA_JUSTIFICADA_SOLO_LA_TOMA';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_07: reclamo de la sesion (v3, legado): aprobar como PRESENTE da REV_029; como EX conserva SES-04 (todos los SJC a EX)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptc3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @e2, @idSesion = @sRec, @categoria = N'CAL',
        @justificacion = N'Reclamo de la sesion', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE2;
    DECLARE @solLegado UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #ptc3 WHERE estado = 1);
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @solLegado, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Presente', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD, @codigoResultadoAprobacion = N'AN';
    IF @solLegado IS NULL OR NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]029|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado est ON est.id = s.estado
                      WHERE s.id = @solLegado AND s.toma IS NULL AND est.codigo = N'P')
        THROW 58190, 'TEST FAILED PC_REC_07: aprobar como PRESENTE un reclamo sin toma debe responder REV_029 sin escribir.', 1;
    TRUNCATE TABLE #ptcK;
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @solLegado, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Justificada', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR (SELECT STRING_AGG(CONCAT(t.numero, N':', rc.codigo), N',') WITHIN GROUP (ORDER BY t.numero)
           FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
           INNER JOIN #ptcEst e ON e.idAsistencia = da.asistencia WHERE e.n = 2) <> N'1:EX,2:EX,3:EX'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia WHERE id = @solLegado AND idToma IS NULL AND codigoResultadoAprobacion = N'EX')
        THROW 58191, 'TEST FAILED PC_REC_07: aprobar un reclamo sin toma debe conservar SES-04 (todos los SJC de la sesion a EX).', 1;
    TRUNCATE TABLE #ptcK; TRUNCATE TABLE #ptc3;
    PRINT 'TEST_PASS:PC_REC_07_LEGADO_SESION';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_08: reintento con el mismo resultado = exito sin escrituras; otro resultado o accion = REV_002; resultado invalido = REV_028
    -- --------------------------------------------------------------------------------------------------------
    SET @auditoria = (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@sol AS NVARCHAR(120)));
    SET @corr = NEWID();
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'aprobada',
        @respuestaDocente = N'Reintento', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD, @codigoResultadoAprobacion = N' an ';
    IF NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@sol AS NVARCHAR(120))) <> @auditoria
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @sol AND justificacionRespuesta = 'Verificado en clase')
        THROW 58200, 'TEST FAILED PC_REC_08: el reintento con el mismo resultado debe ser exito sin escrituras ni auditoria.', 1;
    TRUNCATE TABLE #ptcK;
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Otro resultado', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD, @codigoResultadoAprobacion = N'EX';
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'RECHAZADA',
        @respuestaDocente = N'Otra accion', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @d, @accion = N'APROBADA',
        @respuestaDocente = N'Invalido', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD, @codigoResultadoAprobacion = N'SJC';
    IF (SELECT COUNT(*) FROM #ptcK WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]002|%') <> 2
       OR NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]028|%')
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE resourceId = CAST(@sol AS NVARCHAR(120))) <> @auditoria
       OR NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa INNER JOIN #ptcEst e ON e.idAsistencia = da.asistencia
                      WHERE e.n = 1 AND da.toma = @r2 AND rc.codigo = N'AN')
        THROW 58201, 'TEST FAILED PC_REC_08: otro resultado u otra accion sobre una solicitud resuelta da REV_002; un resultado fuera de AN/EX da REV_028.', 1;
    TRUNCATE TABLE #ptcK;
    PRINT 'TEST_PASS:PC_REC_08_IDEMPOTENCIA_Y_RESULTADO';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_09: un reclamo retirado permite radicar otro de la misma toma; uno rechazado no (REV_027)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e5, @idSesion = @sRec, @idToma = @r3, @categoria = N'CAL',
        @justificacion = N'Primero', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE5;
    DECLARE @solA UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #ptc4 WHERE estado = 1);
    TRUNCATE TABLE #ptc4;
    INSERT INTO #ptcK EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @solA, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE5;
    IF @solA IS NULL OR NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e5 AND idToma = @r3 AND idSolicitudRevision IS NULL AND esReclamable = 1)
        THROW 58210, 'TEST FAILED PC_REC_09: retirar el reclamo de la toma debe dejarla reclamable de nuevo.', 1;
    TRUNCATE TABLE #ptcK;
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e5, @idSesion = @sRec, @idToma = @r3, @categoria = N'CAL',
        @justificacion = N'Segundo', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE5;
    DECLARE @solB UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #ptc4 WHERE estado = 1);
    TRUNCATE TABLE #ptc4;
    INSERT INTO #ptcK EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @solB, @idDocente = @d, @accion = N'RECHAZADA',
        @respuestaDocente = N'No procede', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    SET @corr = NEWID();
    INSERT INTO #ptc4 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @e5, @idSesion = @sRec, @idToma = @r3, @categoria = N'CAL',
        @justificacion = N'Tercero', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE5;
    IF @solB IS NULL OR @solB = @solA OR NOT EXISTS (SELECT 1 FROM #ptcK WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM #ptc4 WHERE estado = 0 AND mt LIKE N'DBCODE=REV[_]027|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_toma_estudiante WHERE idEstudiante = @e5 AND idToma = @r3 AND idSolicitudRevision = @solB
                        AND codigoEstadoSolicitud = N'R' AND codigoRazonCausa = N'SJC' AND esReclamable = 0)
        THROW 58211, 'TEST FAILED PC_REC_09: tras el retiro se radica otro reclamo; tras un rechazo la toma ya no se reclama (REV_027).', 1;
    TRUNCATE TABLE #ptc4; TRUNCATE TABLE #ptcK;
    PRINT 'TEST_PASS:PC_REC_09_RETIRADO_PERMITE_OTRO';

    -- --------------------------------------------------------------------------------------------------------
    -- PC_REC_10: consultas de reclamos con la toma (estudiante y detalle del docente)
    -- --------------------------------------------------------------------------------------------------------
    SET @corr = NEWID();
    INSERT INTO #ptcE EXEC dbo.usp_consultar_solicitudes_revision_estudiante @idUsuarioEjecutor = @uE1, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50;
    INSERT INTO #ptcD EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @sol, @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #ptcE) <> 1
       OR NOT EXISTS (SELECT 1 FROM #ptcE WHERE idSolicitudRevisionAsistencia = @sol AND idToma = @r2 AND numeroToma = 2
                        AND fechaPuntoControlUtc = DATEADD(MINUTE, 40, @baseRec) AND codigoResultadoAprobacion = N'AN' AND codigoEstado = N'A')
       OR NOT EXISTS (SELECT 1 FROM #ptcD WHERE idSolicitudRevisionAsistencia = @sol AND idToma = @r2 AND numeroToma = 2 AND codigoResultadoAprobacion = N'AN'
                        AND codigoRazonCausaToma = N'AN' AND minutosSesion = 120 AND minutosAsistidos = 120)
        THROW 58220, 'TEST FAILED PC_REC_10: las consultas de reclamos deben exponer la toma, su punto de control, su marca actual y el resultado.', 1;
    TRUNCATE TABLE #ptcE; TRUNCATE TABLE #ptcD;
    INSERT INTO #ptcD EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @solLegado, @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ptcD WHERE idToma IS NULL AND numeroToma IS NULL AND codigoRazonCausaToma IS NULL AND codigoResultadoAprobacion = N'EX' AND minutosSesion = 120)
        THROW 58221, 'TEST FAILED PC_REC_10: un reclamo de la sesion (sin toma) devuelve las columnas de la toma en NULL.', 1;
    TRUNCATE TABLE #ptcD;
    PRINT 'TEST_PASS:PC_REC_10_CONSULTAS_RECLAMOS';

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
    THROW 58299, 'TEST FAILED PC_TOM: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:PC_TRANCOUNT_ZERO';
PRINT 'TEST END: test_pc_puntos_control';
GO
