-- CULM-001 C.1 (CONTRACT §2.13.1, §2.13.2): fixture del cierre masivo bajo la regla por horas. Se incluye con :r dentro de una
-- transaccion de prueba. Crea un periodo terminado propio, un grupo de la asignatura sembrada del programa A (con docente
-- titular propio) y tres matriculas activas de estudiantes con vinculo al programa A: @egAbs1 y @egAbs2 con falta (SJC) en
-- las 3 sesiones de 1 h (100 % por horas) y @egPres sin asistencia registrada. Variables que deja declaradas:
--   @period, @periodCodeText, @grupoC, @adminUser, @uDocC, @uCoordC, @egAbs1, @egAbs2, @egPres, @estAct, @estFin, @estCanc, @corr.
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @asigC UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
DECLARE @progC UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @uCoordC UNIQUEIDENTIFIER = (SELECT c.usuario FROM dbo.Programa p JOIN dbo.Coordinador c ON c.id = p.coordinador WHERE p.id = @progC);
DECLARE @estAct UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @estFin UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F');
DECLARE @estCanc UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI');
DECLARE @rzSJC UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @modoC UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @cerC UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @tipoCCc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @grupoC UNIQUEIDENTIFIER = NEWID(), @docC UNIQUEIDENTIFIER = NEWID(), @uDocC UNIQUEIDENTIFIER = NEWID();
DECLARE @egAbs1 UNIQUEIDENTIFIER = NEWID(), @egAbs2 UNIQUEIDENTIFIER = NEWID(), @egPres UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 800000 + ABS(CHECKSUM(NEWID()) % 99999);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
IF @institution IS NULL OR @adminUser IS NULL OR @uCoordC IS NULL OR @estAct IS NULL OR @estFin IS NULL OR @estCanc IS NULL OR @rzSJC IS NULL OR @modoC IS NULL OR @cerC IS NULL OR @tipoCCc IS NULL
    THROW 58300, 'TEST FAILED: C cierre fixture: faltan datos sembrados.', 1;
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uDocC, @tipoCCc, 1960000000 + ABS(CHECKSUM(NEWID()) % 9999999), N'CULMC', N'', N'DocCierre', N'', CONCAT(N'culmc.cierre.', CONVERT(NVARCHAR(12), ABS(CHECKSUM(NEWID()))), N'@fixture.invalid'), 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
INSERT INTO dbo.Docente (id, usuario) VALUES (@docC, @uDocC);
INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
VALUES (@period, @institution, N'Periodo QA Cierre C', @periodCode, DATEADD(DAY, -90, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
    cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@grupoC, @asigC, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA Cierre C', 30, 0, 0, 0, @docC);
DECLARE @estC TABLE (k INT PRIMARY KEY, idEstudiante UNIQUEIDENTIFIER);
INSERT INTO @estC (k, idEstudiante)
SELECT ROW_NUMBER() OVER (ORDER BY ep.estudiante), ep.estudiante FROM (SELECT TOP (3) estudiante FROM dbo.EstudiantePrograma WHERE programa = @progC ORDER BY estudiante) ep;
IF (SELECT COUNT(*) FROM @estC) <> 3 THROW 58301, 'TEST FAILED: C cierre fixture: el programa A necesita 3 estudiantes sembrados.', 1;
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
SELECT v.eg, @estAct, e.idEstudiante, @grupoC FROM (VALUES (1, @egAbs1), (2, @egAbs2), (3, @egPres)) v(k, eg) INNER JOIN @estC e ON e.k = v.k;
DECLARE @sesC TABLE (n INT PRIMARY KEY, idSesion UNIQUEIDENTIFIER, idToma UNIQUEIDENTIFIER);
INSERT INTO @sesC VALUES (1, NEWID(), NEWID()), (2, NEWID(), NEWID()), (3, NEWID(), NEWID());
INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
SELECT s.idSesion, CONCAT(N'QA Cierre C ', s.n), s.n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @grupoC,
       DATEADD(HOUR, -1, DATEADD(DAY, -(40 - s.n), SYSUTCDATETIME())), DATEADD(DAY, -(40 - s.n), SYSUTCDATETIME()), N'UTC_V2'
FROM @sesC s;
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT s.idToma, s.idSesion, 1, @modoC, @cerC, 0, @docC, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
FROM @sesC s INNER JOIN dbo.Sesion se ON se.id = s.idSesion;
INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
SELECT NEWID(), x.eg, s.idSesion FROM @sesC s CROSS JOIN (SELECT eg = @egAbs1 UNION ALL SELECT @egAbs2) x;
INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, @rzSJC, se.fechaHoraInicio, se.fechaHoraFin, s.idToma, 0, SYSUTCDATETIME()
FROM dbo.Asistencia a INNER JOIN @sesC s ON s.idSesion = a.sesion INNER JOIN dbo.Sesion se ON se.id = s.idSesion;
