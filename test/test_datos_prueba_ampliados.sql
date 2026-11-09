USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- Verifica el juego de datos de prueba ampliado (test/fixtures/datos_prueba_ampliados.sql) YA APLICADO: conteos, coordinador con
-- dos programas, estudiantes con dos programas, planes compartidos, grupos mixtos, periodos, tomas, sesion cancelada, reclamos con
-- soportes, festivos y estudiantes por encima del 15 % y del 20 % de inasistencia por horas.
-- OPCIONAL y FUERA del gate de CI (test_suite.sql): el gate corre sobre un despliegue limpio, sin el fixture, y los conteos fallarian.
-- Lo ejecuta reset-datos-prueba.ps1 -Mode Base al terminar, o a mano:
--   sqlcmd -S localhost -U sa -C -b -d gestionasistenciadb -i test/test_datos_prueba_ampliados.sql
-- Solo lectura (no escribe). Salida: TEST_PASS:QA_DATOS_<caso> por caso aprobado y TEST FAILED: <caso> <detalle>; THROW si falla alguno.
-- ============================================================================
PRINT 'TEST START: test_datos_prueba_ampliados';
DECLARE @fallos INT = 0;
DECLARE @tz NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATE);
DECLARE @n1 INT, @n2 INT, @n3 INT, @n4 INT, @n5 INT;

-- QA_DATOS_ESTRUCTURA: facultades, programas, decanos, coordinadores, docentes, estudiantes, asignaturas, grupos.
SELECT @n1 = (SELECT COUNT(*) FROM dbo.Facultad), @n2 = (SELECT COUNT(*) FROM dbo.Programa),
       @n3 = (SELECT COUNT(DISTINCT decano) FROM dbo.Facultad), @n4 = (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE N'qa.coordinador.%' OR correo LIKE N'qa.docente%'),
       @n5 = (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE N'qa.estudiante%');
IF @n1 >= 3 AND @n2 >= 6 AND @n3 >= 3 AND @n4 = 10 AND @n5 = 30
   AND (SELECT COUNT(*) FROM dbo.Facultad WHERE nombre LIKE N'QA-%') = 2 AND (SELECT COUNT(*) FROM dbo.Programa WHERE nombre LIKE N'QA-%') = 5
   AND (SELECT COUNT(*) FROM dbo.Coordinador c INNER JOIN dbo.Usuario u ON u.id = c.usuario WHERE u.correo LIKE N'qa.coordinador.%') = 4
   AND (SELECT COUNT(*) FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.correo LIKE N'qa.docente%') = 6
   AND (SELECT COUNT(*) FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.correo LIKE N'qa.estudiante%') = 30
   AND (SELECT COUNT(*) FROM dbo.Asignatura WHERE codigo LIKE N'QA-%') = 8 AND (SELECT COUNT(*) FROM dbo.Grupo WHERE nombre LIKE N'QA-%') = 8
    PRINT 'TEST_PASS:QA_DATOS_ESTRUCTURA';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_ESTRUCTURA facultades=', @n1, ' programas=', @n2, ' decanos=', @n3, ' coord+doc=', @n4, ' estudiantes=', @n5); SET @fallos += 1; END

-- QA_DATOS_COORDINADOR_DOS_PROGRAMAS: un coordinador nuevo con 2 programas y otros tres con 1.
IF EXISTS (SELECT 1 FROM dbo.Programa p WHERE p.nombre LIKE N'QA-%' GROUP BY p.coordinador HAVING COUNT(*) = 2)
   AND (SELECT COUNT(*) FROM (SELECT p.coordinador FROM dbo.Programa p WHERE p.nombre LIKE N'QA-%' GROUP BY p.coordinador HAVING COUNT(*) = 1) x) = 3
    PRINT 'TEST_PASS:QA_DATOS_COORDINADOR_DOS_PROGRAMAS';
ELSE BEGIN PRINT 'TEST FAILED: QA_DATOS_COORDINADOR_DOS_PROGRAMAS'; SET @fallos += 1; END

-- QA_DATOS_ESTUDIANTES_DOS_PROGRAMAS: 10 de los 30 estudiantes con exactamente 2 programas, los otros 20 con 1.
SELECT @n1 = SUM(IIF(x.programas = 2, 1, 0)), @n2 = SUM(IIF(x.programas = 1, 1, 0))
FROM (SELECT e.id, COUNT(ep.id) AS programas FROM dbo.Estudiante e INNER JOIN dbo.Usuario u ON u.id = e.usuario AND u.correo LIKE N'qa.estudiante%'
      LEFT JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id GROUP BY e.id) x;
IF @n1 = 10 AND @n2 = 20 PRINT 'TEST_PASS:QA_DATOS_ESTUDIANTES_DOS_PROGRAMAS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_ESTUDIANTES_DOS_PROGRAMAS con2=', @n1, ' con1=', @n2); SET @fallos += 1; END

-- QA_DATOS_PLANES_COMPARTIDOS: 5 planes nuevos; al menos 3 asignaturas QA en 2 o mas planes; hay vinculos OBL y OPT.
SELECT @n1 = (SELECT COUNT(*) FROM dbo.PlanEstudio pe INNER JOIN dbo.Programa p ON p.id = pe.programa WHERE p.nombre LIKE N'QA-%'),
       @n2 = (SELECT COUNT(*) FROM (SELECT ape.asignatura FROM dbo.AsignaturaPlanEstudio ape INNER JOIN dbo.Asignatura a ON a.id = ape.asignatura AND a.codigo LIKE N'QA-%'
                                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                                    WHERE ape.estaActivo = 1 GROUP BY ape.asignatura HAVING COUNT(DISTINCT spe.planEstudio) >= 2) c),
       @n3 = (SELECT COUNT(DISTINCT car.codigo) FROM dbo.AsignaturaPlanEstudio ape INNER JOIN dbo.Asignatura a ON a.id = ape.asignatura AND a.codigo LIKE N'QA-%'
              INNER JOIN dbo.CaracterAsignaturaPlan car ON car.id = ape.caracter);
IF @n1 = 5 AND @n2 >= 3 AND @n3 = 2 PRINT 'TEST_PASS:QA_DATOS_PLANES_COMPARTIDOS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_PLANES_COMPARTIDOS planes=', @n1, ' compartidas=', @n2, ' caracteres=', @n3); SET @fallos += 1; END

-- QA_DATOS_GRUPOS_MIXTOS: al menos 2 grupos QA con matriculas de estudiantes de 2 o mas programas, un docente con 3 grupos y uno sin grupos.
SELECT @n1 = (SELECT COUNT(*) FROM (SELECT g.id FROM dbo.Grupo g INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
                                    INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = eg.estudiante
                                    WHERE g.nombre LIKE N'QA-%' GROUP BY g.id HAVING COUNT(DISTINCT ep.programa) >= 2) m),
       @n2 = (SELECT COUNT(*) FROM (SELECT g.docente FROM dbo.Grupo g WHERE g.nombre LIKE N'QA-%' GROUP BY g.docente HAVING COUNT(*) = 3) d),
       @n3 = (SELECT COUNT(*) FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario AND u.correo LIKE N'qa.docente%'
              WHERE NOT EXISTS (SELECT 1 FROM dbo.Grupo g WHERE g.docente = d.id));
IF @n1 >= 2 AND @n2 = 1 AND @n3 = 1 PRINT 'TEST_PASS:QA_DATOS_GRUPOS_MIXTOS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_GRUPOS_MIXTOS mixtos=', @n1, ' docentesConTresGrupos=', @n2, ' docentesSinGrupos=', @n3); SET @fallos += 1; END

-- QA_DATOS_PERIODOS: un periodo vigente que contiene hoy, con grupos QA, y uno vencido (QA-) con grupos QA.
SELECT @n1 = (SELECT COUNT(DISTINCT pa.id) FROM dbo.PeriodoAcademico pa INNER JOIN dbo.Grupo g ON g.periodoAcademico = pa.id AND g.nombre LIKE N'QA-%'
              WHERE pa.fechaInicio <= @hoy AND pa.fechaFin >= @hoy),
       @n2 = (SELECT COUNT(DISTINCT pa.id) FROM dbo.PeriodoAcademico pa INNER JOIN dbo.Grupo g ON g.periodoAcademico = pa.id AND g.nombre LIKE N'QA-%'
              WHERE pa.fechaFin < @hoy AND pa.nombre LIKE N'QA-%');
IF @n1 = 1 AND @n2 = 1 PRINT 'TEST_PASS:QA_DATOS_PERIODOS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_PERIODOS vigentes=', @n1, ' vencidos=', @n2); SET @fallos += 1; END

-- QA_DATOS_SESIONES_TOMAS: sesiones vencidas con toma, una sola cancelada, sesiones con 2 tomas, y todo detalle QA con toma.
SELECT @n1 = (SELECT COUNT(*) FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo AND g.nombre LIKE N'QA-%' WHERE s.fechaHoraFin < SYSUTCDATETIME()),
       @n2 = (SELECT COUNT(*) FROM dbo.SesionCancelacion sc INNER JOIN dbo.Sesion s ON s.id = sc.sesion INNER JOIN dbo.Grupo g ON g.id = s.grupo AND g.nombre LIKE N'QA-%'),
       @n3 = (SELECT COUNT(*) FROM (SELECT t.sesion FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion INNER JOIN dbo.Grupo g ON g.id = s.grupo AND g.nombre LIKE N'QA-%'
                                    GROUP BY t.sesion HAVING COUNT(*) = 2) d),
       @n4 = (SELECT COUNT(*) FROM dbo.DetalleAsistencia d INNER JOIN dbo.Asistencia a ON a.id = d.asistencia INNER JOIN dbo.Sesion s ON s.id = a.sesion
              INNER JOIN dbo.Grupo g ON g.id = s.grupo AND g.nombre LIKE N'QA-%' WHERE d.toma IS NULL);
IF @n1 >= 90 AND @n2 = 1 AND @n3 > 0 AND @n4 = 0 PRINT 'TEST_PASS:QA_DATOS_SESIONES_TOMAS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_SESIONES_TOMAS vencidas=', @n1, ' canceladas=', @n2, ' sesionesConDosTomas=', @n3, ' detallesSinToma=', @n4); SET @fallos += 1; END

-- QA_DATOS_UMBRAL_15 y QA_DATOS_UMBRAL_20: estudiantes distintos con inasistencia por horas > 15 % y > 20 % en el periodo vigente.
SELECT @n1 = COUNT(DISTINCT IIF(r.porcentajeInasistencia > 15, r.idEstudiante, NULL)), @n2 = COUNT(DISTINCT IIF(r.porcentajeInasistencia > 20, r.idEstudiante, NULL))
FROM dbo.uv_resumen_asistencia_estudiante_grupo r
INNER JOIN dbo.Grupo g ON g.id = r.idGrupo AND g.nombre LIKE N'QA-%'
INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaInicio <= @hoy AND pa.fechaFin >= @hoy;
IF @n1 >= 3 PRINT 'TEST_PASS:QA_DATOS_UMBRAL_15'; ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_UMBRAL_15 estudiantes=', @n1); SET @fallos += 1; END
IF @n2 >= 2 PRINT 'TEST_PASS:QA_DATOS_UMBRAL_20'; ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_UMBRAL_20 estudiantes=', @n2); SET @fallos += 1; END

-- QA_DATOS_RECLAMOS: 3 reclamos QA, uno con 2 soportes adjuntos y uno aceptado (resuelto).
SELECT @n1 = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE nombre LIKE N'REC-QA-%'),
       @n2 = (SELECT COUNT(*) FROM (SELECT a.solicitudRevisionAsistencia FROM dbo.ArchivoSoporte a INNER JOIN dbo.SolicitudRevisionAsistencia s ON s.id = a.solicitudRevisionAsistencia
                                    WHERE s.nombre LIKE N'REC-QA-%' AND a.estado = 'ATTACHED' GROUP BY a.solicitudRevisionAsistencia HAVING COUNT(*) = 2) x),
       @n3 = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado AND e.codigo = N'A' WHERE s.nombre LIKE N'REC-QA-%');
IF @n1 = 3 AND @n2 = 1 AND @n3 = 1 PRINT 'TEST_PASS:QA_DATOS_RECLAMOS';
ELSE BEGIN PRINT CONCAT('TEST FAILED: QA_DATOS_RECLAMOS reclamos=', @n1, ' conDosSoportes=', @n2, ' aceptados=', @n3); SET @fallos += 1; END

-- QA_DATOS_FESTIVOS: los 18 festivos de 2026 sembrados.
IF (SELECT COUNT(*) FROM dbo.DiaFestivo WHERE fuente = N'QA-SEED' AND anio = 2026 AND estaActivo = 1) = 18 PRINT 'TEST_PASS:QA_DATOS_FESTIVOS';
ELSE BEGIN PRINT 'TEST FAILED: QA_DATOS_FESTIVOS'; SET @fallos += 1; END

IF @fallos > 0 THROW 58610, 'test_datos_prueba_ampliados: hay casos fallidos (el fixture no esta aplicado o fue alterado).', 1;
PRINT 'TEST END: test_datos_prueba_ampliados';
GO
