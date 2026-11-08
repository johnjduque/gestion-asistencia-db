-- CULM-001 C.1 (CONTRACT §2.13.1): fixture de las pruebas de alertas y revisiones. Se incluye con :r DENTRO de una transaccion de prueba
-- (no hace COMMIT) y se apoya en el fixture de asignatura compartida de B2NM (grupo mixto G con EA en el programa A, EB en el B y E0 sin
-- vinculo; coordinadores CA y CB, decano D, administrador AD, docente titular T). Agrega 25 sesiones vencidas de 1 h, una toma cerrada
-- por sesion y la asistencia (AN) de los tres estudiantes. Deja declaradas en el lote del llamador:
--   @c (correlacion), @egEA/@egEB/@eg0 (matriculas), @coordB (Coordinador.id de CB), @docT, @estCI, @estA;
--   #c1s (n, idSesion, idToma) con las 25 sesiones. 1 falta SJC = 4 % de inasistencia por horas (4 = 16 %, 5 = 20 %, 9 = 36 %).
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
DECLARE @c UNIQUEIDENTIFIER = NEWID();
DECLARE @modoManualC1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerradaC1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @rzANC1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'AN');
DECLARE @estCI UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'CI');
DECLARE @egEA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @eA);
DECLARE @egEB UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @eB);
DECLARE @eg0  UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @e0);
IF @modoManualC1 IS NULL OR @estCerradaC1 IS NULL OR @rzANC1 IS NULL OR @estCI IS NULL OR @egEA IS NULL OR @egEB IS NULL OR @eg0 IS NULL
    THROW 58000, 'TEST FAILED: C fixture: faltan catalogos de B.2 o las matriculas del grupo mixto.', 1;
IF OBJECT_ID(N'tempdb..#c1s') IS NOT NULL DROP TABLE #c1s;
IF OBJECT_ID(N'tempdb..#c1s') IS NOT NULL DROP TABLE #c1s;
CREATE TABLE #c1s (n INT PRIMARY KEY, idSesion UNIQUEIDENTIFIER, idToma UNIQUEIDENTIFIER);
INSERT INTO #c1s (n, idSesion, idToma)
SELECT v.n, NEWID(), NEWID() FROM (SELECT TOP (25) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_objects) v;
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
SELECT s.idSesion, CONCAT(N'CULMC ', s.n), s.n, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @grupoG,
       DATEADD(HOUR, -1, DATEADD(DAY, -(60 - s.n), SYSUTCDATETIME())), DATEADD(DAY, -(60 - s.n), SYSUTCDATETIME()), N'UTC_V2'
FROM #c1s s;
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
SELECT s.idToma, s.idSesion, 1, @modoManualC1, @estCerradaC1, 0, @docT, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
FROM #c1s s INNER JOIN dbo.Sesion se ON se.id = s.idSesion;
INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
SELECT NEWID(), x.eg, s.idSesion FROM #c1s s CROSS JOIN (SELECT eg = @egEA UNION ALL SELECT @egEB UNION ALL SELECT @eg0) x;
INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 1, @rzANC1, se.fechaHoraInicio, se.fechaHoraFin, s.idToma, 0, SYSUTCDATETIME()
FROM dbo.Asistencia a INNER JOIN #c1s s ON s.idSesion = a.sesion INNER JOIN dbo.Sesion se ON se.id = s.idSesion;
DECLARE @coordB2 UNIQUEIDENTIFIER = (SELECT p.coordinador FROM dbo.Programa p WHERE p.id = @progB);
DECLARE @estA2 UNIQUEIDENTIFIER = @estA;
