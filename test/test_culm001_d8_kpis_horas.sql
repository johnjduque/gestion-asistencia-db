USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012, DEC-024, DEC-044 (9), R-1): comparativas, tendencia y consolidado por HORAS.
-- Cubre D8-01..D8-07 y D8-09 (D8-08, up -> down -> up de la migracion 27, esta en test_culm001_d8.ps1 /
-- test_culm001_d8_migraciones.sql). Fixture por insercion directa dentro de una transaccion revertida.
--
-- FIXTURE (valores esperados calculados a mano; toda hora es entera)
--   Programas A (semilla) y B (nuevo, misma facultad F). Asignatura OPT en los planes de A y B.
--   Estudiantes: eA1, eA2 (vinculo A), eAB (vinculo A y B), eB1 (vinculo B), e0 (sin vinculo), f1..f10 (vinculo A).
--   G1 (OPT, periodo P1, 5 matriculas activas: eA1, eA2, eAB, eB1, e0). Sesiones (UTC 14:00 = 09:00 hora local):
--     S1 03-03 2 h, 2 tomas (minutos 0 y 60): eA1 AN+SJC | eA2 AN+AN | eAB AN+SJC | eB1 SJC+SJC | e0 EX+EX
--       PC (puntos de control): por tramos AN+SJC da 0 h asistidas y 2 h de falta (antes 1 y 1 por el reparto 1/n); los
--       valores de G1 / P1 que dependen de eA1 y eAB cambian por eso (antes: eA1 2/1, eAB 1/2, A 33.33/26.67, B 10.00/40.00,
--       facultad 6 h = 30.00, semana 6 h = 40.00, mes 24.00).
--     S2 03-04 1 h, 1 toma : eA1 AN | eA2 SJC | eAB SJC | eB1 EX | e0 sin fila
--     S3 03-05 1 h CANCELADA, 1 toma: los cinco SJC (no suma en nada)
--     S4 03-10 2 h sin tomas, cabecera Asistencia solo de eA1 (sin detalle)
--   horasDictadas por matricula = 2 + 1 + 2 = 5. Por estudiante (asistidas / falta / excusa / sin registro):
--     eA1 1/2/0/2, eA2 2/1/0/2, eAB 0/3/0/2, eB1 0/2/1/2, e0 0/0/2/3
--   Consolidado fila (G1, A): eA1 + eA2 + eAB, activos 3, horasDictadas (del grupo) = 5.00, D = 5 x 3 = 15: asist 3, falta 6, excusa 0
--     => 20.00 / 40.00 / 0.00 / sin registro = 100 - 60.00 = 40.00
--   Consolidado fila (G1, B): eB1 + eAB, activos 2, horasDictadas (del grupo) = 5.00, D = 10: asist 0, falta 5, excusa 1 => 0.00 / 50.00 / 10.00 / 40.00
--   Comparativa programa A: horasDictadas 15, horasFalta 6 => 40.00; programa B: 10 y 5 => 50.00.
--   Comparativa facultad F (eAB cuenta UNA vez): estudiantes con vinculo eA1, eA2, eAB, eB1 => horasDictadas 4 x 5 = 20,
--     horasFalta 2 + 1 + 3 + 2 = 8 => 40.00 (contando dos veces a eAB serian 25 h y 11 h = 44.00).
--   Tendencia P1 (5 matriculas activas por sesion): semana 03-02..03-08: horasDictadasEstudiante = 2x5 + 1x5 = 15, horasFalta
--     S1 (2+0+2+2+0) + S2 (0+1+1+0+0) = 6 + 2 = 8 => 53.33; semana 03-09..03-15: 10 y 0 => 0.00; mes de marzo: 25 y 8 => 32.00.
--   G2 (periodo P2, una toma y sesiones de 1 h, eA1 y eA2): 3 sesiones; eA1 AN, SJC, SJC; eA2 AN, AN, SJC => D8-04
--     horasDictadas 6, horasFalta 3 => 50.00 igual que la formula por sesiones (3 faltas / 6 sesiones-estudiante).
--   G3 (periodo P3, eA1): tres sesiones de 6667 h (AN), 6667 h (SJC) y 6666 h (EX), una toma cada una; D = 20000 h:
--     100 x 6667 / 20000 = 33.335 => ROUND 33.34 (asistencia), 33.335 => 33.34 (inasistencia), 33.33 (excusa); suma 100.01;
--     sin registro = MAX(0, 100 - 100.01) = 0; el exceso 0.01 se resta del mayor redondeado (empate => asistencia) => 33.33.
--     Esperado final: 33.33 / 33.34 / 33.33 / 0.00 (suman 100.00, ninguno negativo) (D8-09).
--   G4 (periodo P4, f1..f10: F-COO-007): V1 1 h AN f1..f9; V2 1 h AN f1..f8; D = 2 x 10 = 20; asist 17 => 85.00 / 0.00 / 0.00 / 15.00.
--   G5 (periodo P4, eA2, sin sesiones): D = 0 => 0.00 / 0.00 / 0.00 / 0.00 y horasDictadas 0.00.
PRINT 'TEST START: test_culm001_d8_kpis_horas (CULM-001 D.8, DEC-012, DEC-024, R-1)';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @progA UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001', @speA UNIQUEIDENTIFIER = 'D2E3F4A5-0000-0000-0000-000000000001';
DECLARE @asigSeed UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
DECLARE @progB UNIQUEIDENTIFIER = NEWID(), @planB UNIQUEIDENTIFIER = NEWID(), @speB UNIQUEIDENTIFIER = NEWID();
DECLARE @fac UNIQUEIDENTIFIER = (SELECT facultad FROM dbo.Programa WHERE id = @progA);
DECLARE @inst UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @fac);
DECLARE @coordA UNIQUEIDENTIFIER = (SELECT coordinador FROM dbo.Programa WHERE id = @progA);
DECLARE @uCA UNIQUEIDENTIFIER = (SELECT usuario FROM dbo.Coordinador WHERE id = @coordA);
DECLARE @uDec UNIQUEIDENTIFIER = (SELECT d.usuario FROM dbo.Facultad f JOIN dbo.Decano d ON d.id = f.decano WHERE f.id = @fac);
DECLARE @uAdm UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador WHERE institucion = @inst ORDER BY id);
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT tipoDePrograma FROM dbo.Programa WHERE id = @progA);
DECLARE @semB UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre WHERE numero = 7);
DECLARE @area UNIQUEIDENTIFIER = (SELECT area FROM dbo.Asignatura WHERE id = @asigSeed);
DECLARE @comp UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @caracterOPT UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OPT');
IF @tipoCC IS NULL OR @estA IS NULL OR @tipoManual IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL OR @uCA IS NULL OR @uDec IS NULL OR @uAdm IS NULL
   OR @semB IS NULL OR @caracterOPT IS NULL OR @area IS NULL OR @comp IS NULL
    THROW 57800, 'TEST FAILED CULM001_D8: faltan fixtures del seed (coordinador, decano, administrador, semestre 7, caracter OPT).', 1;

CREATE TABLE #d8Co (idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
    nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
    estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
    porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT, totalRegistros INT,
    horasDictadas DECIMAL(12,2), porcentajeExcusa DECIMAL(5,2), porcentajeSinRegistro DECIMAL(5,2));
CREATE TABLE #d8Te (inicioIntervalo DATE, finIntervalo DATE, sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2),
    horasDictadasEstudiante DECIMAL(14,2), horasFalta DECIMAL(14,2));
CREATE TABLE #d8Cf (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), estaActivaFacultad BIT, totalProgramas INT, totalEstudiantes INT,
    estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2),
    horasDictadas DECIMAL(12,2), horasFalta DECIMAL(12,2));
CREATE TABLE #d8Cp (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), estaActivoPrograma BIT, totalEstudiantes INT, estudiantesRiesgo INT, estudiantesPerdida INT,
    tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2),
    horasDictadas DECIMAL(12,2), horasFalta DECIMAL(12,2));
CREATE TABLE #d8S (k NVARCHAR(4) PRIMARY KEY, id UNIQUEIDENTIFIER, grupo NVARCHAR(2), inicio DATETIME2(0), horas INT, tomas INT, cancelada BIT);
CREATE TABLE #d8D (k NVARCHAR(4), est NVARCHAR(4), tomaNum INT, codigo NVARCHAR(5));
CREATE TABLE #d8E (k NVARCHAR(4) PRIMARY KEY, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, n INT);
CREATE TABLE #d8G (k NVARCHAR(2) PRIMARY KEY, id UNIQUEIDENTIFIER, asignatura UNIQUEIDENTIFIER, periodo NVARCHAR(2));
CREATE TABLE #d8EG (est NVARCHAR(4), grupo NVARCHAR(2), id UNIQUEIDENTIFIER);
CREATE TABLE #d8P (k NVARCHAR(2) PRIMARY KEY, id UNIQUEIDENTIFIER);

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();

    -- Programa B de la misma facultad (coordinador de A), plan y semestre; OPT en los planes de A y B
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@progB, @fac, @tipoProg, N'D8-Programa B', @coordA, 1);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@planB, @progB, 99818, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@speB, @planB, @semB);
    DECLARE @asigOPT UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado) VALUES (@asigOPT, CONCAT(N'D8-', @tag), N'D8 Optativa', 3, @area, @comp, 1);
    INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc)
    VALUES (NEWID(), @asigOPT, @speA, @caracterOPT, 1, '2020-01-01'), (NEWID(), @asigOPT, @speB, @caracterOPT, 1, '2020-01-01');

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 986000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Horas', N'CulmD8', N'Doc', N'D8', CONCAT(N'culmd8.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMD8');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO #d8E (k, idUsuario, idEstudiante, n)
    SELECT v.k, NEWID(), NEWID(), ROW_NUMBER() OVER (ORDER BY v.k) FROM (VALUES (N'eA1'),(N'eA2'),(N'eAB'),(N'eB1'),(N'e0'),
        (N'f1'),(N'f2'),(N'f3'),(N'f4'),(N'f5'),(N'f6'),(N'f7'),(N'f8'),(N'f9'),(N'f10')) v(k);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 987000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'D8', e.k), N'CulmD8', N'Est', N'D8',
           CONCAT(N'culmd8.', e.k, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMD8'
    FROM #d8E e;
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #d8E;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
    SELECT NEWID(), e.idEstudiante, v.p FROM #d8E e INNER JOIN (VALUES (N'eA1', @progA), (N'eA2', @progA), (N'eAB', @progA), (N'eAB', @progB), (N'eB1', @progB)) v(k, p) ON v.k = e.k;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) SELECT NEWID(), e.idEstudiante, @progA FROM #d8E e WHERE e.k LIKE N'f%';

    -- Periodos propios P1..P4 (cada KPI se pide con @idPeriodoAcademico explicito)
    INSERT INTO #d8P (k, id) VALUES (N'P1', NEWID()), (N'P2', NEWID()), (N'P3', NEWID()), (N'P4', NEWID());
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    SELECT p.id, @inst, CONCAT(N'CULMD8 ', p.k), 3500000 + ABS(CHECKSUM(NEWID()) % 400000), '2024-01-01', '2026-12-31', 2026 FROM #d8P p;

    INSERT INTO #d8G (k, id, asignatura, periodo) VALUES (N'G1', NEWID(), @asigOPT, N'P1'), (N'G2', NEWID(), @asigSeed, N'P2'),
        (N'G3', NEWID(), @asigSeed, N'P3'), (N'G4', NEWID(), @asigSeed, N'P4'), (N'G5', NEWID(), @asigSeed, N'P4');
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT g.id, g.asignatura, p.id, 949000 + ROW_NUMBER() OVER (ORDER BY g.k) * 7 + ABS(CHECKSUM(NEWID()) % 5), CONCAT(N'CULMD8 ', g.k), 30, 0, 0, 0, @d
    FROM #d8G g INNER JOIN #d8P p ON p.k = g.periodo;
    INSERT INTO #d8EG (est, grupo, id)
    SELECT v.est, v.grupo, NEWID() FROM (VALUES (N'eA1', N'G1'), (N'eA2', N'G1'), (N'eAB', N'G1'), (N'eB1', N'G1'), (N'e0', N'G1'),
        (N'eA1', N'G2'), (N'eA2', N'G2'), (N'eA1', N'G3'), (N'eA2', N'G5')) v(est, grupo);
    INSERT INTO #d8EG (est, grupo, id) SELECT e.k, N'G4', NEWID() FROM #d8E e WHERE e.k LIKE N'f%';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT x.id, @estA, e.idEstudiante, g.id FROM #d8EG x INNER JOIN #d8E e ON e.k = x.est INNER JOIN #d8G g ON g.k = x.grupo;

    -- Sesiones: clave, grupo, inicio UTC, horas, tomas, cancelada
    INSERT INTO #d8S (k, id, grupo, inicio, horas, tomas, cancelada) VALUES
        (N'S1', NEWID(), N'G1', '2026-03-03T14:00:00', 2, 2, 0), (N'S2', NEWID(), N'G1', '2026-03-04T14:00:00', 1, 1, 0),
        (N'S3', NEWID(), N'G1', '2026-03-05T14:00:00', 1, 1, 1), (N'S4', NEWID(), N'G1', '2026-03-10T14:00:00', 2, 0, 0),
        (N'T1', NEWID(), N'G2', '2026-05-05T14:00:00', 1, 1, 0), (N'T2', NEWID(), N'G2', '2026-05-06T14:00:00', 1, 1, 0), (N'T3', NEWID(), N'G2', '2026-05-07T14:00:00', 1, 1, 0),
        (N'U1', NEWID(), N'G3', '2024-01-01T00:00:00', 6667, 1, 0), (N'U2', NEWID(), N'G3', '2024-01-01T00:00:00', 6667, 1, 0), (N'U3', NEWID(), N'G3', '2024-01-01T00:00:00', 6666, 1, 0),
        (N'V1', NEWID(), N'G4', '2026-06-02T14:00:00', 1, 1, 0), (N'V2', NEWID(), N'G4', '2026-06-03T14:00:00', 1, 1, 0);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'CULMD8 ', s.k), ROW_NUMBER() OVER (PARTITION BY s.grupo ORDER BY s.inicio, s.k), CONCAT(N'CD8', s.k, N'-', @tag), 1, g.id,
           s.inicio, DATEADD(HOUR, s.horas, s.inicio), N'UTC_V2'
    FROM #d8S s INNER JOIN #d8G x ON x.k = s.grupo INNER JOIN dbo.Grupo g ON g.id = x.id;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    -- PC (puntos de control): la toma k se abre en inicio + (k - 1) * duracion / n (antes todas en el inicio)
    SELECT NEWID(), s.id, v.n, @modoManual, @estCerrada, 0, @d, CAST(DATEADD(MINUTE, (v.n - 1) * s.horas * 60 / s.tomas, se.fechaHoraInicio) AS DATETIME2(0)),
           CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM #d8S s INNER JOIN dbo.Sesion se ON se.id = s.id INNER JOIN (VALUES (1), (2)) v(n) ON v.n <= s.tomas;

    INSERT INTO #d8D (k, est, tomaNum, codigo) VALUES
        (N'S1', N'eA1', 1, N'AN'), (N'S1', N'eA1', 2, N'SJC'), (N'S1', N'eA2', 1, N'AN'), (N'S1', N'eA2', 2, N'AN'),
        (N'S1', N'eAB', 1, N'AN'), (N'S1', N'eAB', 2, N'SJC'), (N'S1', N'eB1', 1, N'SJC'), (N'S1', N'eB1', 2, N'SJC'),
        (N'S1', N'e0', 1, N'EX'), (N'S1', N'e0', 2, N'EX'),
        (N'S2', N'eA1', 1, N'AN'), (N'S2', N'eA2', 1, N'SJC'), (N'S2', N'eAB', 1, N'SJC'), (N'S2', N'eB1', 1, N'EX'),
        (N'S3', N'eA1', 1, N'SJC'), (N'S3', N'eA2', 1, N'SJC'), (N'S3', N'eAB', 1, N'SJC'), (N'S3', N'eB1', 1, N'SJC'), (N'S3', N'e0', 1, N'SJC'),
        (N'T1', N'eA1', 1, N'AN'), (N'T1', N'eA2', 1, N'AN'), (N'T2', N'eA1', 1, N'SJC'), (N'T2', N'eA2', 1, N'AN'),
        (N'T3', N'eA1', 1, N'SJC'), (N'T3', N'eA2', 1, N'SJC'),
        (N'U1', N'eA1', 1, N'AN'), (N'U2', N'eA1', 1, N'SJC'), (N'U3', N'eA1', 1, N'EX');
    INSERT INTO #d8D (k, est, tomaNum, codigo) SELECT N'V1', e.k, 1, N'AN' FROM #d8E e WHERE e.k LIKE N'f%' AND e.k <> N'f10';
    INSERT INTO #d8D (k, est, tomaNum, codigo) SELECT N'V2', e.k, 1, N'AN' FROM #d8E e WHERE e.k LIKE N'f%' AND e.k NOT IN (N'f9', N'f10');
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), x.id, s.id FROM (SELECT DISTINCT k, est FROM #d8D) dd INNER JOIN #d8S s ON s.k = dd.k INNER JOIN #d8EG x ON x.est = dd.est AND x.grupo = s.grupo;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(dd.codigo = N'AN', 1, 0), rc.id, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM #d8D dd INNER JOIN #d8S s ON s.k = dd.k INNER JOIN dbo.Sesion se ON se.id = s.id
    INNER JOIN #d8EG x ON x.est = dd.est AND x.grupo = s.grupo
    INNER JOIN dbo.Asistencia a ON a.estudianteGrupo = x.id AND a.sesion = s.id
    INNER JOIN dbo.TomaAsistencia t ON t.sesion = s.id AND t.numero = dd.tomaNum
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = dd.codigo;
    -- S4: cabecera Asistencia (sin detalle ni tomas) solo de eA1
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), x.id, s.id FROM #d8S s INNER JOIN #d8EG x ON x.grupo = s.grupo AND x.est = N'eA1' WHERE s.k = N'S4';
    -- S3: cancelada
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT s.id, @tipoManual, N'CULMD8 cancelada', NULL, @uD, NEWID() FROM #d8S s WHERE s.cancelada = 1;

    DECLARE @g1 UNIQUEIDENTIFIER = (SELECT id FROM #d8G WHERE k = N'G1'), @g3 UNIQUEIDENTIFIER = (SELECT id FROM #d8G WHERE k = N'G3');
    DECLARE @g4 UNIQUEIDENTIFIER = (SELECT id FROM #d8G WHERE k = N'G4'), @g5 UNIQUEIDENTIFIER = (SELECT id FROM #d8G WHERE k = N'G5');
    DECLARE @p1 UNIQUEIDENTIFIER = (SELECT id FROM #d8P WHERE k = N'P1'), @p2 UNIQUEIDENTIFIER = (SELECT id FROM #d8P WHERE k = N'P2');
    DECLARE @p3 UNIQUEIDENTIFIER = (SELECT id FROM #d8P WHERE k = N'P3'), @p4 UNIQUEIDENTIFIER = (SELECT id FROM #d8P WHERE k = N'P4');

    -- Sanidad del fixture (si falla, el fixture o la base B2 no son los esperados; no es un fallo de D.8)
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r INNER JOIN #d8E e ON e.idEstudiante = r.idEstudiante
                   WHERE r.idGrupo = @g1 AND e.k = N'eAB' AND r.horasDictadas = 5.000000 AND r.horasAsistidas = 0 AND r.horasFalta = 3.000000 AND r.horasExcusa = 0 AND r.horasSinRegistro = 2.000000)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r INNER JOIN #d8E e ON e.idEstudiante = r.idEstudiante
                   WHERE r.idGrupo = @g3 AND e.k = N'eA1' AND r.horasDictadas = 20000.000000 AND r.horasAsistidas = 6667.000000 AND r.horasFalta = 6667.000000 AND r.horasExcusa = 6666.000000)
        THROW 57801, 'TEST FAILED CULM001_D8: el fixture no produce las horas calculadas a mano (base B.2).', 1;

    -- --------------------------------------------------------------------------------------------------------
    -- D8-01 comparativas (facultad: eAB una sola vez; programas: sin duplicar) + D8-06 (la cancelada no suma)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #d8Cf EXEC dbo.usp_consultar_comparativa_facultades @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @p1;
    IF NOT EXISTS (SELECT 1 FROM #d8Cf WHERE idFacultad = @fac AND horasDictadas = 20.00 AND horasFalta = 8.00 AND porcentajeAusentismo = 40.00)
        THROW 57810, 'TEST FAILED CULM001_D8_01: comparativa de facultades debe dar horasDictadas 20.00, horasFalta 8.00 y 40.00 (PC; eAB una sola vez; la cancelada no suma).', 1;
    INSERT INTO #d8Cp EXEC dbo.usp_consultar_comparativa_programas_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @p1;
    IF NOT EXISTS (SELECT 1 FROM #d8Cp WHERE idPrograma = @progA AND horasDictadas = 15.00 AND horasFalta = 6.00 AND porcentajeAusentismo = 40.00)
       OR NOT EXISTS (SELECT 1 FROM #d8Cp WHERE idPrograma = @progB AND horasDictadas = 10.00 AND horasFalta = 5.00 AND porcentajeAusentismo = 50.00)
        THROW 57811, 'TEST FAILED CULM001_D8_01: comparativa de programas debe dar A 15.00 h / 6.00 h / 40.00 y B 10.00 h / 5.00 h / 50.00 (PC).', 1;
    IF EXISTS (SELECT 1 FROM #d8Cp WHERE idPrograma NOT IN (@progA, @progB) AND (horasDictadas <> 0 OR horasFalta <> 0 OR porcentajeAusentismo IS NOT NULL))
        THROW 57812, 'TEST FAILED CULM001_D8_01: un programa sin horas dictadas debe dar 0.00 h y porcentajeAusentismo NULL.', 1;
    TRUNCATE TABLE #d8Cf; TRUNCATE TABLE #d8Cp;
    PRINT 'TEST_PASS:CULM001_D8_01_COMPARATIVAS';
    PRINT 'TEST_PASS:CULM001_D8_06_CANCELADA_NO_SUMA';

    -- --------------------------------------------------------------------------------------------------------
    -- D8-02 tendencia por semana y por mes
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #d8Te EXEC dbo.usp_consultar_tendencia_ausentismo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @p1, @granularidad = N'SEMANA';
    IF (SELECT COUNT(*) FROM #d8Te) <> 2
       OR NOT EXISTS (SELECT 1 FROM #d8Te WHERE inicioIntervalo = '2026-03-02' AND finIntervalo = '2026-03-08' AND horasDictadasEstudiante = 15.00 AND horasFalta = 8.00 AND porcentajeAusentismo = 53.33)
       OR NOT EXISTS (SELECT 1 FROM #d8Te WHERE inicioIntervalo = '2026-03-09' AND finIntervalo = '2026-03-15' AND horasDictadasEstudiante = 10.00 AND horasFalta = 0.00 AND porcentajeAusentismo = 0.00)
        THROW 57820, 'TEST FAILED CULM001_D8_02: tendencia semanal debe dar 15.00 h / 8.00 h / 53.33 (PC) y 10.00 h / 0.00 h / 0.00.', 1;
    TRUNCATE TABLE #d8Te;
    INSERT INTO #d8Te EXEC dbo.usp_consultar_tendencia_ausentismo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @p1, @granularidad = N'MES';
    IF (SELECT COUNT(*) FROM #d8Te) <> 1
       OR NOT EXISTS (SELECT 1 FROM #d8Te WHERE inicioIntervalo = '2026-03-01' AND finIntervalo = '2026-03-31' AND horasDictadasEstudiante = 25.00 AND horasFalta = 8.00 AND porcentajeAusentismo = 32.00)
        THROW 57821, 'TEST FAILED CULM001_D8_02: tendencia mensual debe dar 25.00 h / 8.00 h / 32.00 (PC).', 1;
    TRUNCATE TABLE #d8Te;
    PRINT 'TEST_PASS:CULM001_D8_02_TENDENCIA';

    -- --------------------------------------------------------------------------------------------------------
    -- D8-03 / D8-07 consolidado: cada porcentaje igual a su esperado; grano (grupo, programa del ambito)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #d8Co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @p1;
    IF NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g1 AND idPrograma = @progA AND estudiantesActivos = 3 AND horasDictadas = 5.00
                   AND porcentajeAsistencia = 20.00 AND porcentajeInasistencia = 40.00 AND porcentajeExcusa = 0.00 AND porcentajeSinRegistro = 40.00)
        THROW 57830, 'TEST FAILED CULM001_D8_03: consolidado (G1, A) debe dar 3 activos, 5.00 h (horas dictadas del grupo) y 20.00 / 40.00 / 0.00 / 40.00 (PC).', 1;
    IF NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g1 AND idPrograma = @progB AND estudiantesActivos = 2 AND horasDictadas = 5.00
                   AND porcentajeAsistencia = 0.00 AND porcentajeInasistencia = 50.00 AND porcentajeExcusa = 10.00 AND porcentajeSinRegistro = 40.00)
        THROW 57831, 'TEST FAILED CULM001_D8_03: consolidado (G1, B) debe dar 2 activos, 5.00 h (horas dictadas del grupo) y 0.00 / 50.00 / 10.00 / 40.00 (PC).', 1;
    IF (SELECT COUNT(*) FROM #d8Co WHERE idGrupo = @g1) <> 2
        THROW 57832, 'TEST FAILED CULM001_D8_07: un grupo de dos programas debe dar una fila por programa del ambito (el decano ve los dos).', 1;
    PRINT 'TEST_PASS:CULM001_D8_07_GRANO_GRUPO_PROGRAMA';
    TRUNCATE TABLE #d8Co;
    INSERT INTO #d8Co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @p1, @idPrograma = @progA;
    IF (SELECT COUNT(*) FROM #d8Co) <> 1
       OR NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g1 AND idPrograma = @progA AND estudiantesActivos = 3 AND porcentajeAsistencia = 20.00 AND porcentajeSinRegistro = 40.00)
        THROW 57833, 'TEST FAILED CULM001_D8_07: el coordinador de A con el filtro de A ve solo la fila (G1, A) con sus tres estudiantes.', 1;
    TRUNCATE TABLE #d8Co;
    -- F-COO-007: 10 activos, 2 sesiones, sin faltas => 85.00 / 0.00 / 0.00 / 15.00 (> 0); y D = 0 => los cuatro 0
    INSERT INTO #d8Co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @p4, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g4 AND estudiantesActivos = 10 AND sesionesEjecutadas = 2 AND horasDictadas = 2.00
                   AND porcentajeAsistencia = 85.00 AND porcentajeInasistencia = 0.00 AND porcentajeExcusa = 0.00 AND porcentajeSinRegistro = 15.00)
        THROW 57834, 'TEST FAILED CULM001_D8_03: F-COO-007 (10 activos, 2 sesiones, sin faltas) debe dar 85.00 / 0.00 / 0.00 / 15.00.', 1;
    IF NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g5 AND estudiantesActivos = 1 AND horasDictadas = 0.00
                   AND porcentajeAsistencia = 0.00 AND porcentajeInasistencia = 0.00 AND porcentajeExcusa = 0.00 AND porcentajeSinRegistro = 0.00)
        THROW 57835, 'TEST FAILED CULM001_D8_03: con D = 0 los cuatro porcentajes deben ser 0.00.', 1;
    TRUNCATE TABLE #d8Co;
    PRINT 'TEST_PASS:CULM001_D8_03_CONSOLIDADO';

    -- --------------------------------------------------------------------------------------------------------
    -- D8-04 regresion: una toma y sesiones de 1 h => igual que la formula por sesiones
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #d8Cf EXEC dbo.usp_consultar_comparativa_facultades @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @p2;
    INSERT INTO #d8Cp EXEC dbo.usp_consultar_comparativa_programas_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @p2;
    INSERT INTO #d8Te EXEC dbo.usp_consultar_tendencia_ausentismo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @p2, @granularidad = N'SEMANA';
    IF NOT EXISTS (SELECT 1 FROM #d8Cf WHERE idFacultad = @fac AND sesionesEjecutadas = 6 AND faltasSinJustaCausa = 3 AND porcentajeAusentismo = 50.00 AND horasDictadas = 6.00 AND horasFalta = 3.00)
       OR NOT EXISTS (SELECT 1 FROM #d8Cp WHERE idPrograma = @progA AND sesionesEjecutadas = 6 AND faltasSinJustaCausa = 3 AND porcentajeAusentismo = 50.00 AND horasDictadas = 6.00 AND horasFalta = 3.00)
       OR NOT EXISTS (SELECT 1 FROM #d8Te WHERE inicioIntervalo = '2026-05-04' AND sesionesEjecutadas = 6 AND faltasSinJustaCausa = 3 AND porcentajeAusentismo = 50.00 AND horasDictadasEstudiante = 6.00 AND horasFalta = 3.00)
        THROW 57840, 'TEST FAILED CULM001_D8_04: con una toma y sesiones de 1 h las horas deben dar lo mismo que las sesiones (3 faltas / 6 sesiones-estudiante = 50.00).', 1;
    TRUNCATE TABLE #d8Te;
    PRINT 'TEST_PASS:CULM001_D8_04_REGRESION_UNA_TOMA';

    -- --------------------------------------------------------------------------------------------------------
    -- D8-09 (R-1): 33.335 / 33.335 / 33.33 => 33.33 / 33.34 / 33.33 / 0.00; suman 100.00 y ninguno es negativo
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #d8Co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @p3, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #d8Co WHERE idGrupo = @g3 AND estudiantesActivos = 1 AND horasDictadas = 20000.00
                   AND porcentajeAsistencia = 33.33 AND porcentajeInasistencia = 33.34 AND porcentajeExcusa = 33.33 AND porcentajeSinRegistro = 0.00)
        THROW 57850, 'TEST FAILED CULM001_D8_09: 33.335 / 33.335 / 33.33 deben quedar 33.33 / 33.34 / 33.33 / 0.00 (el exceso baja la asistencia en el empate).', 1;
    IF EXISTS (SELECT 1 FROM #d8Co WHERE porcentajeAsistencia + porcentajeInasistencia + porcentajeExcusa + porcentajeSinRegistro <> 100.00
                   OR porcentajeAsistencia < 0 OR porcentajeInasistencia < 0 OR porcentajeExcusa < 0 OR porcentajeSinRegistro < 0)
        THROW 57851, 'TEST FAILED CULM001_D8_09: los cuatro porcentajes deben sumar exactamente 100.00 y ninguno ser negativo.', 1;
    TRUNCATE TABLE #d8Co;
    PRINT 'TEST_PASS:CULM001_D8_09_REDONDEO_SUMA_100';

    -- --------------------------------------------------------------------------------------------------------
    -- D8-05 sin literal 'A' (estado de matricula) en los cuatro SP; leen MATRICULA/ESTADO_INSCRITA
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM sys.sql_modules m
               WHERE m.object_id IN (OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'),
                                     OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado'))
                 AND m.definition LIKE N'%''A''%')
       OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_comparativa_facultades'), (N'usp_consultar_comparativa_programas_facultad'),
                                        (N'usp_consultar_tendencia_ausentismo'), (N'usp_consultar_consolidado_asistencia_grupos_paginado')) p(nombre)
                  WHERE NOT EXISTS (SELECT 1 FROM sys.sql_modules m WHERE m.object_id = OBJECT_ID(N'dbo.' + p.nombre) AND m.definition LIKE N'%ESTADO_INSCRITA%'))
        THROW 57860, 'TEST FAILED CULM001_D8_05: los cuatro SP no deben tener el literal A y deben leer MATRICULA/ESTADO_INSCRITA.', 1;
    PRINT 'TEST_PASS:CULM001_D8_05_SIN_LITERAL_A';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 57899, 'TEST FAILED CULM001_D8: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:CULM001_D8_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_d8_kpis_horas';
GO
