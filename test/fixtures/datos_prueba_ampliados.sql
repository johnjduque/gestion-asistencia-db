USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- datos_prueba_ampliados.sql (CULM-001; juego de datos de prueba ampliado y reproducible)
--
-- Amplia la semilla canonica (un usuario por rol, una facultad, un programa, un grupo) para probar ambitos y alertas:
--   3 facultades (la canonica + 2), 6 programas (la canonica + 5), 3 decanos, 4 coordinadores nuevos (uno con 2 programas),
--   6 docentes (uno con 3 grupos y uno sin grupos), 30 estudiantes (10 con 2 programas), 5 planes de estudio nuevos con
--   asignaturas compartidas (OBL/OPT) y el plan canonico, 8 grupos (varios mixtos), el periodo vigente (el canonico) y uno
--   vencido, horarios, sesiones con tomas y asistencias, 1 sesion cancelada por el docente, 3 reclamos (uno con 2 soportes y
--   uno resuelto) y los festivos de Colombia de 2026.
-- Fuera del despliegue y fuera del gate de CI (deploy_schema.ps1 no lee test/): se aplica con
--   AsistenciasUCO-Infra/scripts/database/reset-datos-prueba.ps1 -Mode Base, o con sqlcmd sobre una base ya desplegada.
-- Idempotente: MERGE por id determinista (prefijo 5EEDA000-<tipo>-4000-8000-<n>); volver a ejecutarlo no duplica nada y solo
-- repone nombres. Todos los codigos y nombres nuevos llevan el prefijo QA-. Los catalogos se resuelven por codigo.
-- Las fechas de las sesiones son RELATIVAS al dia de aplicacion (12 sesiones vencidas por grupo y 2 futuras, en dias martes a
-- viernes para no caer en festivos); el grupo del periodo vencido usa fechas relativas a ese periodo.
-- Usuarios solo en BD (correo @uco.edu.co de prueba, contrasena con hash de relleno, sin cuenta en el realm ni IdentidadExterna:
-- el vinculo con el sub de Keycloak se crea en el primer ingreso por correo verificado). Los soportes de los reclamos son solo
-- metadatos: el objeto no existe en MinIO. Las alertas de inasistencia las crea el motor C.1 (job del backend), no este script.
--
-- Estudiantes por encima del umbral (porcentaje de inasistencia por horas, periodo vigente): > 20 %: QA-Estudiante 05 (G1, 25 %),
-- 09 (G5, 20.8 %) y 11 (G2, 25 %); entre 15 % y 20 %: 06 (G1), 13 (G2), 18 (G3) y 19 (G4). Periodo vencido: 21 (25 %, CI) y 27.
-- Rollback: no hay _down; use reset-datos-prueba.ps1 -Mode Restore con un respaldo previo (-Mode Snapshot).
-- ============================================================================
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @A CHAR(9) = '5EEDA000-', @B CHAR(11) = '-4000-8000-';
DECLARE @tz NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATE);
DECLARE @inst UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Institucion ORDER BY id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @esp UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @bas UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'BAS');
DECLARE @ins UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'INS');
DECLARE @obl UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OBL');
DECLARE @opt UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OPT');
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @estF UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'F');
DECLARE @estCI UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'CI');
DECLARE @an UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'AN');
DECLARE @sjc UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'SJC');
DECLARE @ex UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'EX');
DECLARE @recP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = N'P');
DECLARE @recA UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = N'A');
DECLARE @catMED UNIQUEIDENTIFIER = (SELECT id FROM dbo.CategoriaJustificacion WHERE codigo = N'MED');
DECLARE @catOTR UNIQUEIDENTIFIER = (SELECT id FROM dbo.CategoriaJustificacion WHERE codigo = N'OTR');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @modoQr UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 1);
DECLARE @tomaCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @cancelDocente UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @tv UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = N'PLA');
DECLARE @area UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Area ORDER BY id);

-- Entidades canonicas de las que cuelga el juego de datos.
DECLARE @prog0 UNIQUEIDENTIFIER = (SELECT TOP 1 p.id FROM dbo.Programa p
                                   WHERE p.nombre NOT LIKE N'QA-%' AND p.nombre NOT LIKE N'CULM1-%' AND p.nombre NOT LIKE N'B2NM-%' ORDER BY p.nombre, p.id);
DECLARE @fac0 UNIQUEIDENTIFIER = (SELECT facultad FROM dbo.Programa WHERE id = @prog0);
DECLARE @coord0 UNIQUEIDENTIFIER = (SELECT coordinador FROM dbo.Programa WHERE id = @prog0);
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT tipoDePrograma FROM dbo.Programa WHERE id = @prog0);
DECLARE @plan0 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.PlanEstudio WHERE programa = @prog0 ORDER BY id);
DECLARE @sem1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Semestre WHERE numero = 1);
DECLARE @sem2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Semestre WHERE numero = 2);
IF @inst IS NULL OR @tipoCC IS NULL OR @esp IS NULL OR @bas IS NULL OR @ins IS NULL OR @obl IS NULL OR @opt IS NULL OR @estA IS NULL OR @estF IS NULL
   OR @estCI IS NULL OR @an IS NULL OR @sjc IS NULL OR @ex IS NULL OR @recP IS NULL OR @recA IS NULL OR @catMED IS NULL OR @catOTR IS NULL
   OR @modoManual IS NULL OR @modoQr IS NULL OR @tomaCerrada IS NULL OR @cancelDocente IS NULL OR @tv IS NULL OR @area IS NULL
   OR @prog0 IS NULL OR @fac0 IS NULL OR @coord0 IS NULL OR @tipoProg IS NULL OR @plan0 IS NULL OR @sem1 IS NULL OR @sem2 IS NULL
    THROW 58600, 'QA_DATOS: catalogos o entidades canonicas de la semilla no disponibles (aplique migraciones y deploy_schema.ps1).', 1;

-- ---------------------------------------------------------------------------------------------------- 1. Usuarios por rol
-- n: decanos 1-2; coordinadores 11-14; docentes 21-26; estudiantes 101-130.
CREATE TABLE #u (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, nombre NVARCHAR(50), apellido NVARCHAR(50), correo NVARCHAR(100));
INSERT INTO #u (n, id, nombre, apellido, correo)
SELECT v.n, CAST(CONCAT(@A, '0001', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER), v.nombre, N'QA-Prueba', v.correo
FROM (VALUES
    (1, N'Decano Salud',            N'qa.decano.salud@uco.edu.co'),
    (2, N'Decano Empresariales',    N'qa.decano.empresariales@uco.edu.co'),
    (11, N'Coord Industrial',       N'qa.coordinador.industrial@uco.edu.co'),
    (12, N'Coord Salud Dos Prog',   N'qa.coordinador.salud@uco.edu.co'),
    (13, N'Coord Administracion',   N'qa.coordinador.administracion@uco.edu.co'),
    (14, N'Coord Contaduria',       N'qa.coordinador.contaduria@uco.edu.co'),
    (21, N'Docente 01 Tres Grupos', N'qa.docente01@uco.edu.co'),
    (22, N'Docente 02',             N'qa.docente02@uco.edu.co'),
    (23, N'Docente 03',             N'qa.docente03@uco.edu.co'),
    (24, N'Docente 04',             N'qa.docente04@uco.edu.co'),
    (25, N'Docente 05 Periodo Venc',N'qa.docente05@uco.edu.co'),
    (26, N'Docente 06 Sin Grupos',  N'qa.docente06@uco.edu.co')
) v (n, nombre, correo);
INSERT INTO #u (n, id, nombre, apellido, correo)
SELECT 100 + x.i, CAST(CONCAT(@A, '0001', @B, RIGHT(CONCAT('000000000000', 100 + x.i), 12)) AS UNIQUEIDENTIFIER),
       CONCAT(N'Estudiante ', RIGHT(CONCAT('0', x.i), 2)), N'QA-Prueba', CONCAT(N'qa.estudiante', RIGHT(CONCAT('0', x.i), 2), N'@uco.edu.co')
FROM (SELECT TOP 30 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects) x;

MERGE INTO dbo.Usuario AS t
USING (SELECT id, 1970000000 + n AS numero, apellido, nombre, correo FROM #u) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.primerNombre = s.nombre, t.primerApellido = s.apellido, t.correo = s.correo
WHEN NOT MATCHED THEN
    INSERT (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (s.id, @tipoCC, s.numero, s.apellido, N'', s.nombre, N'', s.correo, 1, 1, N'HashRelleno_QA_SinCuenta');

MERGE INTO dbo.Decano AS t
USING (SELECT CAST(CONCAT(@A, '0002', @B, RIGHT(CONCAT('000000000000', n), 12)) AS UNIQUEIDENTIFIER) AS id, id AS usuario FROM #u WHERE n BETWEEN 1 AND 2) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, usuario, estado) VALUES (s.id, s.usuario, 1);

-- ---------------------------------------------------------------------------------------------------- 2. Facultades y programas
-- n = 0 es la entidad canonica; 1.. son nuevas.
CREATE TABLE #f (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, nombre NVARCHAR(50), decanoN INT);
INSERT INTO #f (n, id, nombre, decanoN) VALUES
    (0, @fac0, NULL, NULL),
    (1, CAST(CONCAT(@A, '0003', @B, '000000000001') AS UNIQUEIDENTIFIER), N'QA-Facultad de Ciencias de la Salud', 1),
    (2, CAST(CONCAT(@A, '0003', @B, '000000000002') AS UNIQUEIDENTIFIER), N'QA-Facultad de Ciencias Empresariales', 2);

MERGE INTO dbo.Facultad AS t
USING (SELECT f.id, f.nombre, CAST(CONCAT(@A, '0002', @B, RIGHT(CONCAT('000000000000', f.decanoN), 12)) AS UNIQUEIDENTIFIER) AS decano FROM #f f WHERE f.n > 0) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.nombre = s.nombre
WHEN NOT MATCHED THEN INSERT (id, nombre, institucion, decano, estado) VALUES (s.id, s.nombre, @inst, s.decano, 1);

-- Coordinadores nuevos: 11 -> Industrial, 12 -> Enfermeria y Fisioterapia (2 programas), 13 -> Administracion, 14 -> Contaduria.
CREATE TABLE #c (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, usuarioN INT, facN INT);
INSERT INTO #c (n, id, usuarioN, facN)
SELECT v.n, CAST(CONCAT(@A, '0004', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER), v.n, v.facN
FROM (VALUES (11, 0), (12, 1), (13, 2), (14, 2)) v (n, facN);

MERGE INTO dbo.Coordinador AS t
USING (SELECT c.id, u.id AS usuario, f.id AS facultad FROM #c c INNER JOIN #u u ON u.n = c.usuarioN INNER JOIN #f f ON f.n = c.facN) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, usuario, estado, facultad) VALUES (s.id, s.usuario, 1, s.facultad);

CREATE TABLE #p (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, nombre NVARCHAR(50), facN INT, coordId UNIQUEIDENTIFIER);
INSERT INTO #p (n, id, nombre, facN, coordId)
SELECT v.n, CAST(CONCAT(@A, '0005', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER), v.nombre, v.facN, c.id
FROM (VALUES
    (1, N'QA-Ingenieria Industrial',            0, 11),
    (2, N'QA-Enfermeria',                       1, 12),
    (3, N'QA-Fisioterapia',                     1, 12),
    (4, N'QA-Administracion de Empresas',       2, 13),
    (5, N'QA-Contaduria Publica',               2, 14)
) v (n, nombre, facN, coordN) INNER JOIN #c c ON c.n = v.coordN;
INSERT INTO #p (n, id, nombre, facN, coordId) VALUES (0, @prog0, NULL, 0, @coord0);

MERGE INTO dbo.Programa AS t
USING (SELECT p.id, p.nombre, f.id AS facultad, p.coordId FROM #p p INNER JOIN #f f ON f.n = p.facN WHERE p.n > 0) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.nombre = s.nombre
WHEN NOT MATCHED THEN INSERT (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (s.id, s.facultad, @tipoProg, s.nombre, s.coordId, 1);

-- ---------------------------------------------------------------------------------------------------- 3. Docentes y estudiantes
MERGE INTO dbo.Docente AS t
USING (SELECT CAST(CONCAT(@A, '0006', @B, RIGHT(CONCAT('000000000000', n), 12)) AS UNIQUEIDENTIFIER) AS id, id AS usuario FROM #u WHERE n BETWEEN 21 AND 26) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, usuario) VALUES (s.id, s.usuario);

MERGE INTO dbo.Estudiante AS t
USING (SELECT CAST(CONCAT(@A, '0007', @B, RIGHT(CONCAT('000000000000', n), 12)) AS UNIQUEIDENTIFIER) AS id, id AS usuario FROM #u WHERE n > 100) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, usuario) VALUES (s.id, s.usuario);

-- Programas de cada estudiante (e = 1..30; 10 con dos programas: 15 a 24).
CREATE TABLE #ep (e INT, p INT, PRIMARY KEY (e, p));
INSERT INTO #ep (e, p) VALUES
    (1,0),(2,0),(3,0),(4,1),(5,1),(6,1),(7,2),(8,2),(9,3),(10,3),(11,4),(12,4),(13,5),(14,5),
    (15,0),(15,1),(16,0),(16,1),(17,1),(17,4),(18,1),(18,5),(19,2),(19,3),(20,2),(20,3),(21,2),(21,4),(22,3),(22,5),(23,4),(23,5),(24,4),(24,5),
    (25,1),(26,1),(27,2),(28,2),(29,4),(30,5);

MERGE INTO dbo.EstudiantePrograma AS t
USING (SELECT CAST(CONCAT(@A, '0011', @B, RIGHT(CONCAT('000000000000', e * 10 + p), 12)) AS UNIQUEIDENTIFIER) AS id,
              CAST(CONCAT(@A, '0007', @B, RIGHT(CONCAT('000000000000', 100 + e), 12)) AS UNIQUEIDENTIFIER) AS estudiante, pr.id AS programa
       FROM #ep ep INNER JOIN #p pr ON pr.n = ep.p) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, estudiante, programa) VALUES (s.id, s.estudiante, s.programa);

-- ---------------------------------------------------------------------------------------------------- 4. Planes y asignaturas
-- Un plan nuevo por programa nuevo (n = programa); el programa canonico conserva su plan. Semestres 1 y 2 de cada plan.
CREATE TABLE #pl (p INT PRIMARY KEY, id UNIQUEIDENTIFIER);
INSERT INTO #pl (p, id) SELECT n, CAST(CONCAT(@A, '0008', @B, RIGHT(CONCAT('000000000000', n), 12)) AS UNIQUEIDENTIFIER) FROM #p WHERE n > 0;
INSERT INTO #pl (p, id) VALUES (0, @plan0);

MERGE INTO dbo.PlanEstudio AS t
USING (SELECT pl.id, p.id AS programa, 98100 + pl.p AS inp FROM #pl pl INNER JOIN #p p ON p.n = pl.p WHERE pl.p > 0) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, programa, inp, estado) VALUES (s.id, s.programa, s.inp, 1);

CREATE TABLE #spe (p INT, sem INT, id UNIQUEIDENTIFIER, PRIMARY KEY (p, sem));
INSERT INTO #spe (p, sem, id)
SELECT pl.p, s.sem, CAST(CONCAT(@A, '0009', @B, RIGHT(CONCAT('000000000000', pl.p * 10 + s.sem), 12)) AS UNIQUEIDENTIFIER)
FROM #pl pl CROSS JOIN (VALUES (1), (2)) s (sem);
MERGE INTO dbo.SemestrePlanEstudio AS t
USING (SELECT x.id, pl.id AS planEstudio, IIF(x.sem = 1, @sem1, @sem2) AS semestre FROM #spe x INNER JOIN #pl pl ON pl.p = x.p) AS s
ON t.id = s.id OR (t.planEstudio = s.planEstudio AND t.semestre = s.semestre)
WHEN NOT MATCHED THEN INSERT (id, planEstudio, semestre) VALUES (s.id, s.planEstudio, s.semestre);
-- Si el plan canonico ya tenia el semestre, el id real es el existente: se reasigna para los vinculos.
UPDATE x SET x.id = e.id
FROM #spe x INNER JOIN #pl pl ON pl.p = x.p INNER JOIN dbo.SemestrePlanEstudio e ON e.planEstudio = pl.id AND e.semestre = IIF(x.sem = 1, @sem1, @sem2);

CREATE TABLE #a (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, codigo NVARCHAR(50), nombre NVARCHAR(50), componente UNIQUEIDENTIFIER);
INSERT INTO #a (n, id, codigo, nombre, componente)
SELECT v.n, CAST(CONCAT(@A, '000A', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER), v.codigo, v.nombre, v.comp
FROM (VALUES
    (1, N'QA-MAT101', N'QA-Calculo Diferencial', @bas),
    (2, N'QA-EST201', N'QA-Estadistica Aplicada', @bas),
    (3, N'QA-IND301', N'QA-Investigacion de Operaciones', @esp),
    (4, N'QA-ENF301', N'QA-Cuidado Basico de Enfermeria', @esp),
    (5, N'QA-BIO110', N'QA-Anatomia Humana', @ins),
    (6, N'QA-ADM101', N'QA-Fundamentos de Administracion', @esp),
    (7, N'QA-CON201', N'QA-Contabilidad General', @esp),
    (8, N'QA-SAL220', N'QA-Salud Publica', @ins)
) v (n, codigo, nombre, comp);
MERGE INTO dbo.Asignatura AS t
USING (SELECT id, codigo, nombre, componente FROM #a) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.nombre = s.nombre
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, credito, area, componente, estado) VALUES (s.id, s.codigo, s.nombre, 3, @area, s.componente, 1);

-- Vinculos asignatura-plan: asignatura, programa, semestre, caracter. Compartidas: MAT101 (P0,P1), EST201 (P1,P4,P5), BIO110 (P2,P3),
-- ADM101 (P4,P5), SAL220 (P2,P3,P4).
CREATE TABLE #ap (a INT, p INT, sem INT, obligatoria BIT, PRIMARY KEY (a, p));
INSERT INTO #ap (a, p, sem, obligatoria) VALUES
    (1,0,1,1),(1,1,1,1),
    (2,1,2,1),(2,4,1,1),(2,5,2,0),
    (3,1,2,1),
    (4,2,1,1),
    (5,2,1,1),(5,3,1,1),
    (6,4,1,1),(6,5,1,1),
    (7,5,2,1),
    (8,2,2,0),(8,3,2,0),(8,4,2,0);
MERGE INTO dbo.AsignaturaPlanEstudio AS t
USING (SELECT CAST(CONCAT(@A, '000B', @B, RIGHT(CONCAT('000000000000', ap.a * 100 + ap.p * 10 + ap.sem), 12)) AS UNIQUEIDENTIFIER) AS id,
              a.id AS asignatura, x.id AS spe, IIF(ap.obligatoria = 1, @obl, @opt) AS caracter
       FROM #ap ap INNER JOIN #a a ON a.n = ap.a INNER JOIN #spe x ON x.p = ap.p AND x.sem = ap.sem) AS s
ON t.id = s.id OR (t.asignatura = s.asignatura AND t.semestrePlanEstudio = s.spe)
WHEN NOT MATCHED THEN INSERT (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc) VALUES (s.id, s.asignatura, s.spe, s.caracter, 1, '2026-01-01');

-- ---------------------------------------------------------------------------------------------------- 5. Periodos
-- Vigente: el que contiene hoy (el canonico; si no hay, se crea uno). Vencido: termina antes de que empiece el vigente.
DECLARE @perVig UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.PeriodoAcademico WHERE institucion = @inst AND fechaInicio <= @hoy AND fechaFin >= @hoy ORDER BY fechaFin DESC, id);
IF @perVig IS NULL
BEGIN
    SET @perVig = CAST(CONCAT(@A, '000C', @B, '000000000001') AS UNIQUEIDENTIFIER);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perVig, @inst, N'QA-Periodo vigente', 99002, DATEADD(DAY, -100, @hoy), DATEADD(DAY, 40, @hoy), YEAR(@hoy));
END
DECLARE @iniVig DATE = (SELECT fechaInicio FROM dbo.PeriodoAcademico WHERE id = @perVig);
DECLARE @perVen UNIQUEIDENTIFIER = CAST(CONCAT(@A, '000C', @B, '000000000002') AS UNIQUEIDENTIFIER);
DECLARE @iniVen DATE = DATEADD(DAY, -200, @iniVig);
IF NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perVen)
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perVen, @inst, N'QA-Periodo vencido', 99001, @iniVen, DATEADD(DAY, -20, @iniVig), YEAR(@iniVen));
SET @iniVen = (SELECT fechaInicio FROM dbo.PeriodoAcademico WHERE id = @perVen);

-- ---------------------------------------------------------------------------------------------------- 6. Grupos y horarios
-- dia: 1 = martes ... 4 = viernes (indice desde el lunes = 0). Docentes 21..26. G8 es del periodo vencido.
CREATE TABLE #g (g INT PRIMARY KEY, id UNIQUEIDENTIFIER, a INT, vigente BIT, codigo INT, nombre NVARCHAR(50), d INT, dia INT, ini TIME(0), fin TIME(0), tomas INT);
INSERT INTO #g (g, id, a, vigente, codigo, nombre, d, dia, ini, fin, tomas)
SELECT v.g, CAST(CONCAT(@A, '000D', @B, RIGHT(CONCAT('000000000000', v.g), 12)) AS UNIQUEIDENTIFIER), v.a, v.vigente, 9100 + v.g, v.nombre, v.d, v.dia, v.ini, v.fin, v.tomas
FROM (VALUES
    (1, 1, 1, N'QA-G1 Calculo (mixto Sist+Ind)',   21, 1, '07:00', '09:00', 1),
    (2, 2, 1, N'QA-G2 Estadistica (mixto 3 prog)', 21, 2, '07:00', '09:00', 2),
    (3, 3, 1, N'QA-G3 Inv. de Operaciones',        21, 3, '07:00', '09:00', 1),
    (4, 4, 1, N'QA-G4 Cuidado Basico',             22, 4, '07:00', '09:00', 1),
    (5, 5, 1, N'QA-G5 Anatomia (mixto Enf+Fis)',   22, 1, '09:00', '11:00', 2),
    (6, 6, 1, N'QA-G6 Fund. Administracion (mixto)',23, 2, '09:00', '11:00', 2),
    (7, 7, 1, N'QA-G7 Contabilidad',               24, 3, '09:00', '11:00', 1),
    (8, 8, 0, N'QA-G8 Salud Publica (vencido)',    25, 4, '09:00', '11:00', 1)
) v (g, a, vigente, nombre, d, dia, ini, fin, tomas);

MERGE INTO dbo.Grupo AS t
USING (SELECT g.id, a.id AS asignatura, IIF(g.vigente = 1, @perVig, @perVen) AS periodo, g.codigo, g.nombre,
              CAST(CONCAT(@A, '0006', @B, RIGHT(CONCAT('000000000000', g.d), 12)) AS UNIQUEIDENTIFIER) AS docente,
              IIF(g.vigente = 0, 7, 0) AS finalizaron, IIF(g.vigente = 0, 1, 0) AS cancelaron
       FROM #g g INNER JOIN #a a ON a.n = g.a) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.nombre = s.nombre
WHEN NOT MATCHED THEN INSERT (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (s.id, s.asignatura, s.periodo, s.codigo, s.nombre, 30, s.finalizaron, 0, s.cancelaron, s.docente);

MERGE INTO dbo.Horario AS t
USING (SELECT CAST(CONCAT(@A, '000E', @B, RIGHT(CONCAT('000000000000', g.g), 12)) AS UNIQUEIDENTIFIER) AS id, g.id AS grupo,
              (SELECT id FROM dbo.Dia WHERE codigo = CHOOSE(g.dia + 1, N'LU', N'MA', N'MI', N'JU', N'VI', N'SA', N'DO')) AS dia, g.ini, g.fin
       FROM #g g) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, grupo, dia, horaInicio, horaFin) VALUES (s.id, s.grupo, s.dia, s.ini, s.fin);

-- Vinculo docente-programa (HU091): por cada programa que tiene la asignatura de sus grupos en su plan; el docente 26 queda
-- vinculado a Contaduria sin grupos.
CREATE TABLE #dp (d INT, p INT, PRIMARY KEY (d, p));
INSERT INTO #dp (d, p) SELECT DISTINCT g.d, ap.p FROM #g g INNER JOIN #ap ap ON ap.a = g.a;
INSERT INTO #dp (d, p) VALUES (26, 5);
MERGE INTO dbo.DocentePrograma AS t
USING (SELECT CAST(CONCAT(@A, '000F', @B, RIGHT(CONCAT('000000000000', dp.d * 10 + dp.p), 12)) AS UNIQUEIDENTIFIER) AS id,
              CAST(CONCAT(@A, '0006', @B, RIGHT(CONCAT('000000000000', dp.d), 12)) AS UNIQUEIDENTIFIER) AS docente, p.id AS programa
       FROM #dp dp INNER JOIN #p p ON p.n = dp.p) AS s
ON t.id = s.id OR (t.docente = s.docente AND t.programa = s.programa)
WHEN NOT MATCHED THEN INSERT (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc) VALUES (s.id, s.docente, s.programa, @tv, 1, SYSUTCDATETIME());

-- ---------------------------------------------------------------------------------------------------- 7. Matriculas
CREATE TABLE #eg (g INT, e INT, PRIMARY KEY (g, e));
INSERT INTO #eg (g, e) VALUES
    (1,1),(1,2),(1,3),(1,4),(1,5),(1,6),(1,15),(1,16),(1,25),(1,26),
    (2,4),(2,5),(2,11),(2,12),(2,13),(2,14),(2,17),(2,18),(2,23),(2,24),(2,29),(2,30),
    (3,4),(3,5),(3,6),(3,15),(3,16),(3,17),(3,18),(3,25),(3,26),
    (4,7),(4,8),(4,19),(4,20),(4,21),(4,27),(4,28),
    (5,7),(5,9),(5,10),(5,19),(5,20),(5,22),(5,27),(5,28),
    (6,11),(6,12),(6,13),(6,14),(6,21),(6,23),(6,24),(6,29),(6,30),
    (7,13),(7,14),(7,18),(7,22),(7,23),(7,24),(7,30),
    (8,7),(8,8),(8,9),(8,10),(8,19),(8,20),(8,21),(8,27);
MERGE INTO dbo.EstudianteGrupo AS t
USING (SELECT CAST(CONCAT(@A, '0010', @B, RIGHT(CONCAT('000000000000', eg.g * 100 + eg.e), 12)) AS UNIQUEIDENTIFIER) AS id,
              CAST(CONCAT(@A, '0007', @B, RIGHT(CONCAT('000000000000', 100 + eg.e), 12)) AS UNIQUEIDENTIFIER) AS estudiante, g.id AS grupo,
              CASE WHEN g.vigente = 1 THEN @estA WHEN eg.e = 21 THEN @estCI ELSE @estF END AS estado
       FROM #eg eg INNER JOIN #g g ON g.g = eg.g) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, estado, estudiante, grupo) VALUES (s.id, s.estado, s.estudiante, s.grupo);

-- ---------------------------------------------------------------------------------------------------- 8. Sesiones
-- k = 1..12 vencidas (G8: todas dentro del periodo vencido), 13 y 14 futuras. La sesion 7 del grupo 4 queda cancelada por el docente.
CREATE TABLE #s (g INT, k INT, id UNIQUEIDENTIFIER, inicio DATETIME2(0), fin DATETIME2(0), ejecutada BIT, cancelada BIT, PRIMARY KEY (g, k));
INSERT INTO #s (g, k, id, inicio, fin, ejecutada, cancelada)
SELECT g.g, k.k, CAST(CONCAT(@A, '0012', @B, RIGHT(CONCAT('000000000000', g.g * 100 + k.k), 12)) AS UNIQUEIDENTIFIER),
       CAST((DATEADD(MINUTE, DATEDIFF(MINUTE, '00:00', g.ini), CAST(f.fecha AS DATETIME2(0))) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS DATETIME2(0)),
       CAST((DATEADD(MINUTE, DATEDIFF(MINUTE, '00:00', g.fin), CAST(f.fecha AS DATETIME2(0))) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS DATETIME2(0)),
       IIF(k.k <= 12, 1, 0), IIF(g.g = 4 AND k.k = 7, 1, 0)
FROM #g g
CROSS JOIN (SELECT TOP 14 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k FROM sys.all_objects) k
CROSS APPLY (SELECT fecha = CASE WHEN g.vigente = 1
                 THEN DATEADD(DAY, 7 * (k.k - 12), DATEADD(DAY, -(((DATEDIFF(DAY, '19000101', DATEADD(DAY, -1, @hoy)) - g.dia) % 7 + 7) % 7), DATEADD(DAY, -1, @hoy)))
                 ELSE DATEADD(DAY, 7 * (k.k - 1), DATEADD(DAY, ((g.dia - DATEDIFF(DAY, '19000101', DATEADD(DAY, 7, @iniVen))) % 7 + 7) % 7, DATEADD(DAY, 7, @iniVen))) END) f
WHERE (g.vigente = 1 OR k.k <= 12);
DELETE s FROM #s s INNER JOIN #g g ON g.g = s.g
WHERE g.vigente = 1 AND CAST(s.inicio AS DATE) < @iniVig;

MERGE INTO dbo.Sesion AS t
USING (SELECT s.id, CONCAT(N'QA-Sesion G', s.g, N'-', RIGHT(CONCAT('0', s.k), 2)) AS nombre, s.k AS numero, CONCAT(N'SES-', RIGHT(CONCAT('0', s.k), 2)) AS codigo,
              g.id AS grupo, s.inicio, s.fin
       FROM #s s INNER JOIN #g g ON g.g = s.g) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (s.id, s.nombre, s.numero, s.codigo, s.numero, s.grupo, s.inicio, s.fin, N'UTC_V2');

-- Cancelacion decidida por el docente (la sesion queda sin tomas ni asistencias: no suma horas dictadas).
MERGE INTO dbo.SesionCancelacion AS t
USING (SELECT s.id AS sesion, d.usuario AS usuario, s.id AS correlacion
       FROM #s s INNER JOIN #g g ON g.g = s.g INNER JOIN dbo.Docente d ON d.id = CAST(CONCAT(@A, '0006', @B, RIGHT(CONCAT('000000000000', g.d), 12)) AS UNIQUEIDENTIFIER)
       WHERE s.cancelada = 1) AS s
ON t.sesion = s.sesion
WHEN NOT MATCHED THEN INSERT (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
    VALUES (s.sesion, @cancelDocente, N'QA-Sesion cancelada por el docente (juego de datos de prueba)', NULL, s.usuario, SYSUTCDATETIME(), s.correlacion);

-- ---------------------------------------------------------------------------------------------------- 9. Tomas, asistencias y detalles
-- Plan de faltas por estudiante y grupo. Tipo F = falta en todas las tomas de la sesion; E = excusa (EX) en todas; T2 = falta solo en
-- la toma 2. Lo demas es asistencia (AN). Con sesiones de 2 h: 1 toma = 2 h; 2 tomas = 1 h cada una (24 h dictadas por grupo).
CREATE TABLE #fl (g INT, e INT, tipo VARCHAR(2), sesiones VARCHAR(40));
INSERT INTO #fl (g, e, tipo, sesiones) VALUES
    (1, 5, 'F', '2,6,10'), (1, 6, 'F', '4,9'), (1, 2, 'F', '5'), (1, 15, 'F', '1'), (1, 15, 'E', '3,7'), (1, 25, 'E', '8'),
    (2, 11, 'E', '1'), (2, 11, 'F', '2,3'), (2, 11, 'T2', '5,6'), (2, 13, 'T2', '1,3,4,7'), (2, 17, 'T2', '2,6'), (2, 23, 'E', '3'),
    (3, 4, 'F', '1'), (3, 18, 'F', '5,9'), (3, 26, 'E', '4'),
    (4, 19, 'F', '1,5'), (4, 7, 'F', '2'), (4, 28, 'E', '3'),
    (5, 9, 'T2', '2,4,6,8,10'), (5, 10, 'T2', '3'), (5, 22, 'F', '5'),
    (6, 21, 'F', '3'), (6, 24, 'T2', '7,8'),
    (7, 30, 'F', '1'), (7, 24, 'F', '2'), (7, 18, 'F', '4'),
    (8, 7, 'F', '1'), (8, 27, 'F', '3,8'), (8, 21, 'F', '2,5,9');
CREATE TABLE #fs (g INT, e INT, k INT, tipo VARCHAR(2), PRIMARY KEY (g, e, k));
INSERT INTO #fs (g, e, k, tipo)
SELECT f.g, f.e, CAST(TRIM(x.value) AS INT), f.tipo FROM #fl f CROSS APPLY STRING_SPLIT(f.sesiones, ',') x;

CREATE TABLE #t (g INT, k INT, t INT, id UNIQUEIDENTIFIER, sesion UNIQUEIDENTIFIER, apertura DATETIME2(0), cierre DATETIME2(0), modo UNIQUEIDENTIFIER, implicita BIT, docente UNIQUEIDENTIFIER, PRIMARY KEY (g, k, t));
INSERT INTO #t (g, k, t, id, sesion, apertura, cierre, modo, implicita, docente)
SELECT s.g, s.k, n.t, CAST(CONCAT(@A, '0014', @B, RIGHT(CONCAT('000000000000', s.g * 1000 + s.k * 10 + n.t), 12)) AS UNIQUEIDENTIFIER), s.id,
       DATEADD(MINUTE, (n.t - 1) * (DATEDIFF(MINUTE, s.inicio, s.fin) / g.tomas), s.inicio),
       DATEADD(MINUTE, (n.t - 1) * (DATEDIFF(MINUTE, s.inicio, s.fin) / g.tomas) + 15, s.inicio),
       IIF(n.t = 2, @modoQr, @modoManual), IIF(g.tomas = 1, 1, 0),
       CAST(CONCAT(@A, '0006', @B, RIGHT(CONCAT('000000000000', g.d), 12)) AS UNIQUEIDENTIFIER)
FROM #s s INNER JOIN #g g ON g.g = s.g INNER JOIN (VALUES (1), (2)) n (t) ON n.t <= g.tomas
WHERE s.ejecutada = 1 AND s.cancelada = 0;
MERGE INTO dbo.TomaAsistencia AS t
USING (SELECT id, sesion, t AS numero, modo, implicita, docente, apertura, cierre, id AS corr FROM #t) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
    VALUES (s.id, s.sesion, s.numero, s.modo, @tomaCerrada, s.implicita, s.docente, s.apertura, s.cierre, 0, s.corr, s.corr);

-- Cabeceras: una por matricula y sesion ejecutada.
MERGE INTO dbo.Asistencia AS t
USING (SELECT CAST(CONCAT(@A, '0013', @B, RIGHT(CONCAT('000000000000', s.g * 10000 + s.k * 100 + eg.e), 12)) AS UNIQUEIDENTIFIER) AS id,
              CAST(CONCAT(@A, '0010', @B, RIGHT(CONCAT('000000000000', eg.g * 100 + eg.e), 12)) AS UNIQUEIDENTIFIER) AS estudianteGrupo, s.id AS sesion
       FROM #s s INNER JOIN #eg eg ON eg.g = s.g WHERE s.ejecutada = 1 AND s.cancelada = 0) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, estudianteGrupo, sesion) VALUES (s.id, s.estudianteGrupo, s.sesion);

-- Detalles: una fila por cabecera y toma. El codigo continua la numeracion global solo para las filas nuevas.
DECLARE @baseCodigo INT = (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
MERGE INTO dbo.DetalleAsistencia AS t
USING (SELECT x.id, @baseCodigo + ROW_NUMBER() OVER (ORDER BY x.n) AS codigo, x.asistencia, x.asistio, x.razon, x.inicio, x.fin, x.toma, x.porEstudiante, x.fechaRegistro
       FROM (SELECT CAST(CONCAT(@A, '0015', @B, RIGHT(CONCAT('000000000000', (s.g * 10000 + s.k * 100 + eg.e) * 10 + tm.t), 12)) AS UNIQUEIDENTIFIER) AS id,
                    (s.g * 10000 + s.k * 100 + eg.e) * 10 + tm.t AS n,
                    CAST(CONCAT(@A, '0013', @B, RIGHT(CONCAT('000000000000', s.g * 10000 + s.k * 100 + eg.e), 12)) AS UNIQUEIDENTIFIER) AS asistencia,
                    CAST(IIF(fs.tipo IN ('F', 'E') OR (fs.tipo = 'T2' AND tm.t = 2), 0, 1) AS BIT) AS asistio,
                    CASE WHEN fs.tipo = 'E' THEN @ex WHEN fs.tipo = 'F' OR (fs.tipo = 'T2' AND tm.t = 2) THEN @sjc ELSE @an END AS razon,
                    s.inicio, s.fin, tm.id AS toma,
                    CAST(IIF(tm.t = 2 AND fs.tipo IS NULL, 1, 0) AS BIT) AS porEstudiante,
                    IIF(tm.t = 2 AND fs.tipo IS NULL, DATEADD(MINUTE, 5, tm.apertura), NULL) AS fechaRegistro
             FROM #s s INNER JOIN #eg eg ON eg.g = s.g INNER JOIN #t tm ON tm.g = s.g AND tm.k = s.k
             LEFT JOIN #fs fs ON fs.g = s.g AND fs.e = eg.e AND fs.k = s.k
             WHERE s.ejecutada = 1 AND s.cancelada = 0
               AND NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia d WHERE d.id = CAST(CONCAT(@A, '0015', @B, RIGHT(CONCAT('000000000000', (s.g * 10000 + s.k * 100 + eg.e) * 10 + tm.t), 12)) AS UNIQUEIDENTIFIER))) x) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    VALUES (s.id, s.codigo, s.asistencia, s.asistio, s.razon, s.inicio, s.fin, s.toma, s.porEstudiante, s.fechaRegistro);

UPDATE tm SET tm.totalAusentesMarcados = (SELECT COUNT(*) FROM dbo.DetalleAsistencia d WHERE d.toma = tm.id AND d.asistio = 0)
FROM dbo.TomaAsistencia tm INNER JOIN #t q ON q.id = tm.id;

-- ---------------------------------------------------------------------------------------------------- 10. Reclamos y soportes
-- R1 (G1, sesion 2, Estudiante 05): pendiente con 2 soportes. R2 (G2, sesion 1, Estudiante 11): aceptada (la asistencia ya es EX,
-- como la deja usp_resolver_solicitud_revision_asistencia) con 1 soporte. R3 (G1, sesion 4, Estudiante 06): pendiente sin soportes.
CREATE TABLE #r (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, g INT, k INT, e INT, estado UNIQUEIDENTIFIER, cat UNIQUEIDENTIFIER, texto VARCHAR(200), respuesta VARCHAR(200), dias INT);
INSERT INTO #r (n, id, g, k, e, estado, cat, texto, respuesta, dias)
SELECT v.n, CAST(CONCAT(@A, '0016', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER), v.g, v.k, v.e, v.estado, v.cat, v.texto, v.respuesta, v.dias
FROM (VALUES
    (1, 1, 2, 5,  @recP, @catMED, 'QA: incapacidad medica adjunta para la sesion 2.', '', 2),
    (2, 2, 1, 11, @recA, @catMED, 'QA: certificado medico de la sesion 1.', 'QA: aprobada por el docente titular.', 5),
    (3, 1, 4, 6,  @recP, @catOTR, 'QA: calamidad domestica en la sesion 4.', '', 1)
) v (n, g, k, e, estado, cat, texto, respuesta, dias);
MERGE INTO dbo.SolicitudRevisionAsistencia AS t
USING (SELECT r.id, CONCAT(N'REC-QA-', RIGHT(CONCAT('00', r.n), 3)) AS nombre,
              CAST(CONCAT(@A, '0013', @B, RIGHT(CONCAT('000000000000', r.g * 10000 + r.k * 100 + r.e), 12)) AS UNIQUEIDENTIFIER) AS asistencia,
              DATEADD(DAY, -r.dias, @hoy) AS fecha, r.estado, r.cat, r.texto, r.respuesta FROM #r r) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta, categoriaJustificacion)
    VALUES (s.id, s.nombre, s.asistencia, s.fecha, s.estado, s.texto, s.respuesta, s.cat);

MERGE INTO dbo.ArchivoSoporte AS t
USING (SELECT CAST(CONCAT(@A, '0017', @B, RIGHT(CONCAT('000000000000', v.n), 12)) AS UNIQUEIDENTIFIER) AS id,
              CAST(CONCAT(@A, '0001', @B, RIGHT(CONCAT('000000000000', 100 + r.e), 12)) AS UNIQUEIDENTIFIER) AS propietario, r.id AS solicitud,
              v.nombre, v.tipo, v.bytes, LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONCAT('QA-soporte-', v.n)), 2)) AS checksum
       FROM (VALUES (1, 1, N'QA-incapacidad-medica.pdf', 'application/pdf', 48213),
                    (2, 1, N'QA-historia-clinica.png', 'image/png', 20480),
                    (3, 2, N'QA-certificado-medico.jpg', 'image/jpeg', 30720)) v (n, r, nombre, tipo, bytes)
       INNER JOIN #r r ON r.n = v.r) AS s
ON t.id = s.id
WHEN NOT MATCHED THEN INSERT (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes, checksumSha256, estado,
        fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
    VALUES (s.id, s.propietario, s.solicitud, s.nombre, s.tipo, s.bytes, s.checksum, 'ATTACHED', SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), s.id, s.id);

-- ---------------------------------------------------------------------------------------------------- 11. Festivos de Colombia 2026
MERGE INTO dbo.DiaFestivo AS t
USING (SELECT CAST(CONCAT(@A, '0020', @B, RIGHT(CONCAT('000000000000', DATEPART(DAYOFYEAR, v.fecha)), 12)) AS UNIQUEIDENTIFIER) AS id, v.fecha, v.nombre
       FROM (VALUES
           (CAST('2026-01-01' AS DATE), N'Ano Nuevo'), ('2026-01-12', N'Reyes Magos'), ('2026-03-23', N'San Jose'), ('2026-04-02', N'Jueves Santo'),
           ('2026-04-03', N'Viernes Santo'), ('2026-05-01', N'Dia del Trabajo'), ('2026-05-18', N'Ascension del Senor'), ('2026-06-08', N'Corpus Christi'),
           ('2026-06-15', N'Sagrado Corazon'), ('2026-06-29', N'San Pedro y San Pablo'), ('2026-07-20', N'Independencia de Colombia'),
           ('2026-08-07', N'Batalla de Boyaca'), ('2026-08-17', N'Asuncion de la Virgen'), ('2026-10-12', N'Dia de la Raza'),
           ('2026-11-02', N'Todos los Santos'), ('2026-11-16', N'Independencia de Cartagena'), ('2026-12-08', N'Inmaculada Concepcion'),
           ('2026-12-25', N'Navidad')) v (fecha, nombre)) AS s
ON t.fecha = s.fecha
WHEN NOT MATCHED THEN INSERT (id, fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga) VALUES (s.id, s.fecha, CONCAT(N'QA-', s.nombre), N'QA-SEED', 1, SYSUTCDATETIME(), s.id);

COMMIT TRANSACTION;
DECLARE @resumen NVARCHAR(400) = CONCAT(N'QA_DATOS aplicado: facultades=', (SELECT COUNT(*) FROM dbo.Facultad), N' programas=', (SELECT COUNT(*) FROM dbo.Programa),
             N' grupos QA=', (SELECT COUNT(*) FROM dbo.Grupo WHERE nombre LIKE N'QA-%'), N' estudiantes QA=', (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE N'qa.estudiante%'));
PRINT @resumen;
GO
SET XACT_ABORT OFF;
GO
