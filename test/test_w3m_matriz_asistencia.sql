USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CIERRE-W3M (docs/work-items/CIERRE-W3M-matriz-asistencia): la matriz de asistencia del grupo y el resumen de sesiones del
-- docente se resuelven en la base (DEC-066: estados por tramos entre tomas, uv_asistencia_sesion_horas).
--   usp_consultar_matriz_asistencia_grupo_docente_paginado (nuevo), usp_consultar_resumen_sesiones_grupo_docente (nuevo) y
--   usp_consultar_resumen_asistencia_grupo_docente_paginado + @busqueda (resultset sin cambios, 39 columnas).
--   W3M_MAT_01_CELDAS        estados conocidos: PRESENTE, AUSENTE, JUSTIFICADA, SIN_REGISTRO, PARCIAL y NO_DISPONIBLE (cancelada)
--   W3M_MAT_02_COMO_LA_VISTA cada celda con registro coincide con codigoEstadoSesionEstudiante y los minutos de la vista
--   W3M_MAT_03_PAGINACION    paginas por ESTUDIANTE: total, orden, sin repetidos; las celdas de cada pagina son las del alumno
--   W3M_MAT_04_BUSQUEDA      nombre y documento; vacio = sin filtro; sin coincidencias = 0 filas
--   W3M_MAT_05_SIN_SESIONES  un grupo sin sesiones devuelve una fila por estudiante con idSesion NULL
--   W3M_MAT_06_RESUMEN_BUSQ  el resumen por horas acepta @busqueda y su total es el filtrado; sin ella devuelve todo
--   W3M_SES_01_ESTADOS       estado temporal de cada sesion (EJECUTADA, CANCELADA, EN_CURSO, PROGRAMADA, horario indeterminado)
--   W3M_SES_02_CONTEOS       presentes, parciales, justificadas, ausentes y sinRegistro por sesion sobre las matriculas activas
--   W3M_SES_03_GRUPO         conteos del grupo, sesion en curso y proxima, activos, en riesgo y promedio
--   W3M_SES_04_SIN_SESIONES  grupo sin sesiones: una fila con idSesion NULL y las columnas del grupo
--   W3M_AMB_01_RECHAZOS      otro docente: SEC_002; grupo inexistente: ERR_GRUPO_NO_EXISTE; coordinador y decano: SEC_001; paginacion invalida: PAG_001
--   W3M_TRANCOUNT_ZERO
-- Fixtures por insercion directa (sesiones con horas relativas a SYSUTCDATETIME) dentro de una transaccion revertida; los
-- rechazos van al final y fuera de ella porque los SP usan XACT_ABORT ON.
PRINT 'TEST START: test_w3m_matriz_asistencia (CIERRE-W3M)';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoI UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'I');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @idAsig UNIQUEIDENTIFIER, @idInst UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idInst = pr.idInstitucion
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_asignatura_plan_estudio apx ON apx.idAsignatura = a.id INNER JOIN dbo.uv_semestre_plan_estudio spe ON apx.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id
WHERE pr.estaActivoPrograma = 1 AND a.estaActivaAsignatura = 1
ORDER BY a.id;
IF @tipoCC IS NULL OR @estadoA IS NULL OR @estadoI IS NULL OR @tipoManual IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL OR @idAsig IS NULL
    THROW 59300, 'TEST FAILED W3M: faltan fixtures del seed (tipo CC, estados A e I, cancelacion manual, toma manual cerrada, asignatura activa).', 1;

CREATE TABLE #w3mM (idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), documento NVARCHAR(20),
    codigoEstadoEstudiante NVARCHAR(10), totalRegistros INT, idSesion UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), minutosAsistidos INT, minutosSesion INT);
CREATE TABLE #w3mS (idSesion UNIQUEIDENTIFIER, numero INT, nombre NVARCHAR(200), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    procedenciaTemporal NVARCHAR(24), estadoSesion NVARCHAR(20), estadoSolicitud NVARCHAR(50), pendienteAprobacion BIT, totalEstudiantes INT,
    presentes INT, parciales INT, justificadas INT, ausentes INT, sinRegistro INT, sesionesProgramadas INT, sesionesEjecutadas INT,
    sesionesCanceladas INT, sesionesEnCurso INT, idSesionEnCurso UNIQUEIDENTIFIER, idSesionProxima UNIQUEIDENTIFIER, estudiantesActivos INT,
    estudiantesEnRiesgo INT, promedioAsistencia DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
CREATE TABLE #w3mR (c01 SQL_VARIANT, c02 SQL_VARIANT, c03 SQL_VARIANT, c04 SQL_VARIANT, c05 SQL_VARIANT, c06 SQL_VARIANT, c07 SQL_VARIANT, c08 SQL_VARIANT,
    c09 SQL_VARIANT, c10 SQL_VARIANT, c11 SQL_VARIANT, c12 SQL_VARIANT, c13 SQL_VARIANT, c14 SQL_VARIANT, c15 SQL_VARIANT, c16 SQL_VARIANT, c17 SQL_VARIANT,
    c18 SQL_VARIANT, c19 SQL_VARIANT, c20 SQL_VARIANT, c21 SQL_VARIANT, c22 SQL_VARIANT, c23 SQL_VARIANT, c24 SQL_VARIANT, c25 SQL_VARIANT, c26 SQL_VARIANT,
    c27 SQL_VARIANT, c28 SQL_VARIANT, c29 SQL_VARIANT, c30 SQL_VARIANT, c31 SQL_VARIANT, c32 SQL_VARIANT, c33 SQL_VARIANT, c34 SQL_VARIANT, c35 SQL_VARIANT,
    c36 SQL_VARIANT, c37 SQL_VARIANT, c38 SQL_VARIANT, c39 SQL_VARIANT);

DECLARE @corr UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(8) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 8);
    CREATE TABLE #w3mE (n INT PRIMARY KEY, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER, doc BIGINT);
    INSERT INTO #w3mE (n, idUsuario, idEstudiante, idEG, doc)
    SELECT v.n, NEWID(), NEWID(), NEWID(), 961000000 + v.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999) FROM (VALUES (1),(2),(3),(4),(5)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uD, @tipoCC, 960000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Matriz', N'W3m', N'Doc', N'W3m', CONCAT(N'w3m.d.', @tag, N'@test.local'), 1, 1);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    SELECT e.idUsuario, @tipoCC, e.doc, CONCAT(N'W3m', @tag, e.n), N'Mx', N'Est', N'W3m', CONCAT(N'w3m.e', e.n, N'.', @tag, N'@test.local'), 1, 1
    FROM #w3mE e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #w3mE;

    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInst, N'W3M periodo matriz', 3500000 + ABS(CHECKSUM(NEWID()) % 400000), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g1, @idAsig, @per, 958000 + ABS(CHECKSUM(NEWID()) % 20000), N'W3M Grupo con sesiones', 30, 0, 0, 0, @d),
           (@g2, @idAsig, @per, 979000 + ABS(CHECKSUM(NEWID()) % 20000), N'W3M Grupo sin sesiones', 30, 0, 0, 0, @d);
    -- G1: E1..E4 activos y E5 inactivo; G2: E1 y E2 activos (sin sesiones)
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT e.idEG, IIF(e.n = 5, @estadoI, @estadoA), e.idEstudiante, @g1 FROM #w3mE e;
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT NEWID(), @estadoA, e.idEstudiante, @g2 FROM #w3mE e WHERE e.n <= 2;

    -- Sesiones de G1: clave, numero, horas de duracion, desplazamiento del inicio en horas respecto de ahora, tomas, procedencia
    CREATE TABLE #w3mSe (k NVARCHAR(4) PRIMARY KEY, id UNIQUEIDENTIFIER, numero INT, horas INT, inicioHoras INT, tomas INT, procedencia NVARCHAR(24));
    INSERT INTO #w3mSe (k, id, numero, horas, inicioHoras, tomas, procedencia) VALUES
        (N'S1', NEWID(), 1, 2, -72, 2, N'UTC_V2'),    -- ejecutada: 2 h, 2 tomas
        (N'S2', NEWID(), 2, 4, -50, 4, N'UTC_V2'),    -- ejecutada: 4 h, 4 tomas
        (N'S3', NEWID(), 3, 2, -30, 0, N'UTC_V2'),    -- cancelada
        (N'S4', NEWID(), 4, 2, -1, 0, N'UTC_V2'),     -- en curso: inicio hace 1 h, fin dentro de 1 h
        (N'S5', NEWID(), 5, 2, 24, 0, N'UTC_V2'),     -- proxima: manana
        (N'S6', NEWID(), 6, 2, -20, 0, NULL);         -- horario no confirmado (procedencia NULL), en el pasado
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'W3M ', s.k), s.numero, CONCAT(N'W3M', @tag, s.k), 1, @g1,
           DATEADD(HOUR, s.inicioHoras, SYSUTCDATETIME()), DATEADD(HOUR, s.inicioHoras + s.horas, SYSUTCDATETIME()), s.procedencia
    FROM #w3mSe s;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, v.n, @modoManual, @estCerrada, 0, @d,
           CAST(DATEADD(MINUTE, (v.n - 1) * s.horas * 60 / s.tomas, DATEADD(NANOSECOND, -DATEPART(NANOSECOND, se.fechaHoraInicio), se.fechaHoraInicio)) AS DATETIME2(0)),
           CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM #w3mSe s INNER JOIN dbo.Sesion se ON se.id = s.id
    INNER JOIN (VALUES (1), (2), (3), (4)) v(n) ON v.n <= s.tomas;
    -- Marcas por sesion, estudiante y numero de toma
    CREATE TABLE #w3mD (k NVARCHAR(4), est INT, tomaNum INT, codigo NVARCHAR(5));
    INSERT INTO #w3mD (k, est, tomaNum, codigo) VALUES
        (N'S1', 1, 1, N'AN'), (N'S1', 1, 2, N'AN'), (N'S1', 2, 1, N'SJC'), (N'S1', 2, 2, N'SJC'), (N'S1', 3, 1, N'EX'), (N'S1', 3, 2, N'EX'),
        (N'S2', 1, 1, N'AN'), (N'S2', 1, 2, N'AN'), (N'S2', 1, 3, N'AN'), (N'S2', 1, 4, N'SJC'),
        (N'S2', 2, 1, N'AN'), (N'S2', 2, 2, N'AN'), (N'S2', 2, 3, N'AN'), (N'S2', 2, 4, N'AN'),
        (N'S2', 3, 1, N'AN'), (N'S2', 3, 2, N'AN'), (N'S2', 3, 3, N'AN'), (N'S2', 3, 4, N'AN'),
        (N'S2', 5, 1, N'AN'), (N'S2', 5, 2, N'AN'), (N'S2', 5, 3, N'AN'), (N'S2', 5, 4, N'AN');
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), e.idEG, s.id FROM (SELECT DISTINCT k, est FROM #w3mD) d INNER JOIN #w3mSe s ON s.k = d.k INNER JOIN #w3mE e ON e.n = d.est;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(d.codigo = N'AN', 1, 0), rc.id, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM #w3mD d INNER JOIN #w3mSe s ON s.k = d.k INNER JOIN dbo.Sesion se ON se.id = s.id
    INNER JOIN #w3mE e ON e.n = d.est
    INNER JOIN dbo.Asistencia a ON a.estudianteGrupo = e.idEG AND a.sesion = s.id
    INNER JOIN dbo.TomaAsistencia t ON t.sesion = s.id AND t.numero = d.tomaNum
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = d.codigo;
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT s.id, @tipoManual, N'W3M cancelada', NULL, @uD, NEWID() FROM #w3mSe s WHERE s.k = N'S3';

    DECLARE @s1 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S1'), @s2 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S2');
    DECLARE @s3 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S3'), @s4 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S4');
    DECLARE @s5 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S5'), @s6 UNIQUEIDENTIFIER = (SELECT id FROM #w3mSe WHERE k = N'S6');
    DECLARE @e1 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #w3mE WHERE n = 1), @e2 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #w3mE WHERE n = 2);
    DECLARE @e3 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #w3mE WHERE n = 3), @e4 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #w3mE WHERE n = 4);
    DECLARE @e5 UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #w3mE WHERE n = 5);
    DECLARE @doc3 NVARCHAR(20) = (SELECT CONVERT(NVARCHAR(20), doc) FROM #w3mE WHERE n = 3);
    DECLARE @rows INT, @total INT, @x NVARCHAR(40);

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_01: todas las matriculas (5) x todas las sesiones (6) en una sola pagina, con los estados esperados
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50;
    SELECT @rows = COUNT(1), @total = MAX(totalRegistros) FROM #w3mM;
    IF @rows <> 30 OR @total <> 5 OR (SELECT COUNT(DISTINCT idEstudiante) FROM #w3mM) <> 5
        THROW 59301, 'TEST FAILED W3M_MAT_01_CELDAS: se esperaban 5 estudiantes x 6 sesiones y totalRegistros = 5.', 1;
    -- la primera fila de un estudiante es la sesion de menor numero
    IF (SELECT TOP 1 idSesion FROM #w3mM WHERE idEstudiante = @e1) <> @s1
        THROW 59303, 'TEST FAILED W3M_MAT_01_CELDAS: la primera fila de cada estudiante debe ser la sesion numero 1.', 1;
    IF NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e1 AND idSesion = @s1 AND codigoEstado = N'PRESENTE' AND minutosAsistidos = 120 AND minutosSesion = 120)
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e2 AND idSesion = @s1 AND codigoEstado = N'AUSENTE' AND minutosAsistidos = 0)
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e3 AND idSesion = @s1 AND codigoEstado = N'JUSTIFICADA')
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e4 AND idSesion = @s1 AND codigoEstado = N'SIN_REGISTRO' AND minutosAsistidos = 0 AND minutosSesion = 120)
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e2 AND idSesion = @s2 AND codigoEstado = N'PRESENTE' AND minutosAsistidos = 240)
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e1 AND idSesion = @s2 AND codigoEstado = N'PARCIAL' AND minutosAsistidos > 0 AND minutosAsistidos < 240)
       OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e5 AND idSesion = @s2 AND codigoEstado = N'PRESENTE' AND codigoEstadoEstudiante = N'I')
       OR EXISTS (SELECT 1 FROM #w3mM WHERE idSesion = @s3 AND codigoEstado <> N'NO_DISPONIBLE')
       OR EXISTS (SELECT 1 FROM #w3mM WHERE idSesion IN (@s4, @s5, @s6) AND codigoEstado <> N'SIN_REGISTRO')
        THROW 59304, 'TEST FAILED W3M_MAT_01_CELDAS: estados de celda inesperados.', 1;
    PRINT 'TEST_PASS:W3M_MAT_01_CELDAS';

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_02: cada celda con registro sale de uv_asistencia_sesion_horas (la misma vista que los reportes)
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM #w3mM m INNER JOIN dbo.uv_asistencia_sesion_horas h ON h.idEstudianteGrupo = m.idEstudianteGrupo AND h.idSesion = m.idSesion
               WHERE m.codigoEstado <> h.codigoEstadoSesionEstudiante OR m.minutosAsistidos <> h.minutosAsistidos OR m.minutosSesion <> h.minutosSesion)
       OR (SELECT COUNT(1) FROM #w3mM m INNER JOIN dbo.uv_asistencia_sesion_horas h ON h.idEstudianteGrupo = m.idEstudianteGrupo AND h.idSesion = m.idSesion) <> 7
        THROW 59305, 'TEST FAILED W3M_MAT_02_COMO_LA_VISTA: la matriz difiere de uv_asistencia_sesion_horas.', 1;
    PRINT 'TEST_PASS:W3M_MAT_02_COMO_LA_VISTA';

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_03: paginas de 2 estudiantes (2 + 2 + 1), orden por nombre, sin repetidos y con las 6 celdas de cada uno
    -- --------------------------------------------------------------------------------------------------------
    CREATE TABLE #w3mO (pagina INT, idEstudiante UNIQUEIDENTIFIER, nombre NVARCHAR(400), celdas INT, total INT);
    DECLARE @p INT = 1;
    WHILE @p <= 3
    BEGIN
        DELETE FROM #w3mM;
        INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
            @idGrupo = @g1, @numeroPagina = @p, @tamanoPagina = 2;
        INSERT INTO #w3mO SELECT @p, idEstudiante, MIN(nombreCompletoEstudiante), COUNT(1), MAX(totalRegistros) FROM #w3mM GROUP BY idEstudiante;
        SET @p += 1;
    END;
    IF (SELECT COUNT(1) FROM #w3mO) <> 5 OR (SELECT COUNT(DISTINCT idEstudiante) FROM #w3mO) <> 5
       OR EXISTS (SELECT 1 FROM #w3mO WHERE celdas <> 6 OR total <> 5)
       OR (SELECT COUNT(1) FROM #w3mO WHERE pagina = 3) <> 1
        THROW 59306, 'TEST FAILED W3M_MAT_03_PAGINACION: las paginas deben repartir 5 estudiantes (2, 2 y 1) con 6 celdas cada uno.', 1;
    -- orden por nombre completo entre paginas (el mismo del resumen por horas): ningun estudiante de una pagina anterior va despues
    IF EXISTS (SELECT 1 FROM #w3mO x INNER JOIN #w3mO y ON x.pagina < y.pagina AND (x.nombre > y.nombre OR (x.nombre = y.nombre AND x.idEstudiante > y.idEstudiante)))
        THROW 59307, 'TEST FAILED W3M_MAT_03_PAGINACION: las paginas deben respetar el orden por nombre.', 1;
    DROP TABLE #w3mO;
    PRINT 'TEST_PASS:W3M_MAT_03_PAGINACION';

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_04: busqueda por nombre (apellido con el tag y el digito) y por documento; vacio = todos; sin coincidencias = 0
    -- --------------------------------------------------------------------------------------------------------
    DELETE FROM #w3mM;
    SET @x = CONCAT(@tag, N'2');
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = @x;
    IF (SELECT COUNT(DISTINCT idEstudiante) FROM #w3mM) <> 1 OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e2) OR (SELECT MAX(totalRegistros) FROM #w3mM) <> 1
        THROW 59309, 'TEST FAILED W3M_MAT_04_BUSQUEDA: la busqueda por nombre debe dar un solo estudiante y total 1.', 1;
    DELETE FROM #w3mM;
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = @doc3;
    IF (SELECT COUNT(DISTINCT idEstudiante) FROM #w3mM) <> 1 OR NOT EXISTS (SELECT 1 FROM #w3mM WHERE idEstudiante = @e3 AND documento = @doc3)
        THROW 59310, 'TEST FAILED W3M_MAT_04_BUSQUEDA: la busqueda por documento debe dar el estudiante 3.', 1;
    DELETE FROM #w3mM;
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'   ';
    IF (SELECT COUNT(DISTINCT idEstudiante) FROM #w3mM) <> 5
        THROW 59311, 'TEST FAILED W3M_MAT_04_BUSQUEDA: una busqueda de espacios equivale a sin filtro.', 1;
    DELETE FROM #w3mM;
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'zzzNoExiste987';
    IF EXISTS (SELECT 1 FROM #w3mM)
        THROW 59312, 'TEST FAILED W3M_MAT_04_BUSQUEDA: sin coincidencias debe haber 0 filas.', 1;
    PRINT 'TEST_PASS:W3M_MAT_04_BUSQUEDA';

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_05: grupo sin sesiones -> una fila por estudiante con idSesion NULL
    -- --------------------------------------------------------------------------------------------------------
    DELETE FROM #w3mM;
    INSERT INTO #w3mM EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g2, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(1) FROM #w3mM) <> 2 OR EXISTS (SELECT 1 FROM #w3mM WHERE idSesion IS NOT NULL OR codigoEstado IS NOT NULL OR totalRegistros <> 2)
        THROW 59313, 'TEST FAILED W3M_MAT_05_SIN_SESIONES: 2 filas con idSesion NULL y total 2.', 1;
    PRINT 'TEST_PASS:W3M_MAT_05_SIN_SESIONES';

    -- --------------------------------------------------------------------------------------------------------
    -- W3M_MAT_06: el resumen por horas acepta @busqueda; sin ella devuelve todas las matriculas (compatibilidad)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #w3mR EXEC dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(1) FROM #w3mR) <> 5 OR (SELECT MAX(CONVERT(INT, c29)) FROM #w3mR) <> 5
        THROW 59314, 'TEST FAILED W3M_MAT_06_RESUMEN_BUSQ: sin busqueda el resumen debe traer las 5 matriculas.', 1;
    DELETE FROM #w3mR;
    INSERT INTO #w3mR EXEC dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = @doc3;
    IF (SELECT COUNT(1) FROM #w3mR) <> 1 OR (SELECT MAX(CONVERT(INT, c29)) FROM #w3mR) <> 1 OR (SELECT CONVERT(UNIQUEIDENTIFIER, c02) FROM #w3mR) <> @e3
        THROW 59315, 'TEST FAILED W3M_MAT_06_RESUMEN_BUSQ: la busqueda por documento debe dar la matricula del estudiante 3 con total 1.', 1;
    DELETE FROM #w3mR;
    INSERT INTO #w3mR EXEC dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @uD, @idCorrelacion = @corr,
        @idGrupo = @g1, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = @x;
    IF (SELECT COUNT(1) FROM #w3mR) <> 1 OR (SELECT CONVERT(UNIQUEIDENTIFIER, c02) FROM #w3mR) <> @e2
        THROW 59316, 'TEST FAILED W3M_MAT_06_RESUMEN_BUSQ: la busqueda por nombre debe dar la matricula del estudiante 2.', 1;
    PRINT 'TEST_PASS:W3M_MAT_06_RESUMEN_BUSQ';

    -- --------------------------------------------------------------------------------------------------------
    -- Resumen de sesiones del grupo (G1)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #w3mS EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idGrupo = @g1;
    IF (SELECT COUNT(1) FROM #w3mS) <> 6
        THROW 59317, 'TEST FAILED W3M_SES_01_ESTADOS: una fila por sesion (6).', 1;
    IF (SELECT TOP 1 idSesion FROM #w3mS ORDER BY numero) <> @s1 OR (SELECT TOP 1 idSesion FROM #w3mS ORDER BY numero DESC) <> @s6
        THROW 59318, 'TEST FAILED W3M_SES_01_ESTADOS: orden por numero.', 1;
    IF NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s1 AND estadoSesion = N'EJECUTADA')
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s2 AND estadoSesion = N'EJECUTADA')
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s3 AND estadoSesion = N'CANCELADA')
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s4 AND estadoSesion = N'EN_CURSO')
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s5 AND estadoSesion = N'PROGRAMADA')
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s6 AND estadoSesion = N'PROGRAMADA' AND procedenciaTemporal IS NULL)
        THROW 59319, 'TEST FAILED W3M_SES_01_ESTADOS: estado temporal de las sesiones.', 1;
    PRINT 'TEST_PASS:W3M_SES_01_ESTADOS';

    -- Conteos sobre las 4 matriculas ACTIVAS (el inactivo E5 no cuenta aunque asistio a S2)
    IF NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s1 AND totalEstudiantes = 4 AND presentes = 1 AND parciales = 0 AND justificadas = 1 AND ausentes = 1 AND sinRegistro = 1)
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s2 AND totalEstudiantes = 4 AND presentes = 2 AND parciales = 1 AND justificadas = 0 AND ausentes = 0 AND sinRegistro = 1)
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s3 AND presentes = 0 AND parciales = 0 AND justificadas = 0 AND ausentes = 0 AND sinRegistro = 0)
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s4 AND presentes = 0 AND sinRegistro = 4)
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion = @s5 AND presentes = 0 AND sinRegistro = 4)
        THROW 59320, 'TEST FAILED W3M_SES_02_CONTEOS: conteos por sesion inesperados.', 1;
    PRINT 'TEST_PASS:W3M_SES_02_CONTEOS';

    -- Grupo: 6 programadas, 2 ejecutadas, 1 cancelada, 1 en curso; en curso S4; proxima S5 (S6 no esta confirmada)
    IF EXISTS (SELECT 1 FROM #w3mS WHERE sesionesProgramadas <> 6 OR sesionesEjecutadas <> 2 OR sesionesCanceladas <> 1 OR sesionesEnCurso <> 1
                                         OR idSesionEnCurso <> @s4 OR idSesionProxima <> @s5 OR estudiantesActivos <> 4)
        THROW 59321, 'TEST FAILED W3M_SES_03_GRUPO: conteos del grupo.', 1;
    -- Indicadores: los de uv_resumen_asistencia_estudiante_grupo de las matriculas activas (E2 pierde por 2 h de falta de 6 h dictadas)
    IF EXISTS (SELECT 1 FROM #w3mS s CROSS JOIN (
                   SELECT enRiesgo = SUM(IIF(r.codigoPermanencia IN (N'RIESGO', N'PERDIDA'), 1, 0)), promedio = CAST(AVG(r.porcentajeAsistenciaHoras) AS DECIMAL(5,2))
                   FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idGrupo = @g1 AND r.codigoEstadoEstudiante = N'A') o
               WHERE s.estudiantesEnRiesgo <> o.enRiesgo OR s.promedioAsistencia <> o.promedio)
       OR EXISTS (SELECT 1 FROM #w3mS WHERE estudiantesEnRiesgo < 1 OR promedioAsistencia IS NULL OR promedioAsistencia <= 0 OR promedioAsistencia >= 100
                                          OR umbralAdvertencia IS NULL OR umbralPerdida IS NULL)
        THROW 59322, 'TEST FAILED W3M_SES_03_GRUPO: indicadores del grupo (en riesgo, promedio y umbrales).', 1;
    PRINT 'TEST_PASS:W3M_SES_03_GRUPO';

    DELETE FROM #w3mS;
    INSERT INTO #w3mS EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = @uD, @idCorrelacion = @corr, @idGrupo = @g2;
    IF (SELECT COUNT(1) FROM #w3mS) <> 1
       OR NOT EXISTS (SELECT 1 FROM #w3mS WHERE idSesion IS NULL AND sesionesProgramadas = 0 AND sesionesEjecutadas = 0 AND sesionesCanceladas = 0 AND sesionesEnCurso = 0
                                             AND idSesionEnCurso IS NULL AND idSesionProxima IS NULL AND estudiantesActivos = 2 AND estudiantesEnRiesgo = 0 AND promedioAsistencia IS NULL)
        THROW 59323, 'TEST FAILED W3M_SES_04_SIN_SESIONES: una fila con idSesion NULL y las columnas del grupo en cero.', 1;
    PRINT 'TEST_PASS:W3M_SES_04_SIN_SESIONES';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(2048) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    THROW 59399, @err, 1;
END CATCH;
DROP TABLE IF EXISTS #w3mM, #w3mS, #w3mR;
GO

-- W3M_AMB_01: rechazos del catalogo con el seed (fuera de transaccion: los SP usan XACT_ABORT ON)
DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER, @userCoord UNIQUEIDENTIFIER, @userDec UNIQUEIDENTIFIER;
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @msg NVARCHAR(4000), @rechazos INT = 0, @i INT = 0;
SELECT TOP 1 @group = g.id, @teacher = g.docente FROM dbo.Grupo g WHERE g.docente IS NOT NULL ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @userT2 = d.usuario FROM dbo.Docente d WHERE d.id <> @teacher ORDER BY d.id;
SELECT TOP 1 @userCoord = idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1 AND estaActivoRolCoordinador = 1 ORDER BY id;
SELECT TOP 1 @userDec = idUsuario FROM dbo.uv_decano_identidad WHERE estaActivoUsuario = 1 ORDER BY id;
IF @group IS NULL OR @userT IS NULL OR @userT2 IS NULL OR @userCoord IS NULL OR @userDec IS NULL
    THROW 59330, 'TEST FAILED W3M_AMB_01: faltan fixtures del seed (grupo con docente, otro docente, coordinador y decano).', 1;
CREATE TABLE #w3mM2 (idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400), documento NVARCHAR(20),
    codigoEstadoEstudiante NVARCHAR(10), totalRegistros INT, idSesion UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), minutosAsistidos INT, minutosSesion INT);
CREATE TABLE #w3mS2 (idSesion UNIQUEIDENTIFIER, numero INT, nombre NVARCHAR(200), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    procedenciaTemporal NVARCHAR(24), estadoSesion NVARCHAR(20), estadoSolicitud NVARCHAR(50), pendienteAprobacion BIT, totalEstudiantes INT,
    presentes INT, parciales INT, justificadas INT, ausentes INT, sinRegistro INT, sesionesProgramadas INT, sesionesEjecutadas INT,
    sesionesCanceladas INT, sesionesEnCurso INT, idSesionEnCurso UNIQUEIDENTIFIER, idSesionProxima UNIQUEIDENTIFIER, estudiantesActivos INT,
    estudiantesEnRiesgo INT, promedioAsistencia DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
-- 1) otro docente en un grupo ajeno: SEC_002; 2) grupo inexistente: ERR_GRUPO_NO_EXISTE (matriz y resumen de sesiones)
DECLARE @casos TABLE (n INT, ejecutor UNIQUEIDENTIFIER, grupo UNIQUEIDENTIFIER, codigo NVARCHAR(30), pagina INT, tamano INT);
INSERT INTO @casos VALUES (1, @userT2, @group, N'SEC_002', 1, 10), (2, @userT, @corr, N'ERR_GRUPO_NO_EXISTE', 1, 10),
                          (3, @userCoord, @group, N'SEC_001', 1, 10), (4, @userDec, @group, N'SEC_001', 1, 10),
                          (5, @userT, @group, N'PAG_001', 0, 10), (6, @userT, @group, N'PAG_001', 1, 100000);
DECLARE @n INT, @ej UNIQUEIDENTIFIER, @gr UNIQUEIDENTIFIER, @cod NVARCHAR(30), @pg INT, @tm INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT n, ejecutor, grupo, codigo, pagina, tamano FROM @casos ORDER BY n;
OPEN c;
FETCH NEXT FROM c INTO @n, @ej, @gr, @cod, @pg, @tm;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @msg = NULL;
    BEGIN TRY
        INSERT INTO #w3mM2 EXEC dbo.usp_consultar_matriz_asistencia_grupo_docente_paginado @idUsuarioEjecutor = @ej, @idCorrelacion = @corr,
            @idGrupo = @gr, @numeroPagina = @pg, @tamanoPagina = @tm;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
    END CATCH;
    IF @msg IS NOT NULL AND CHARINDEX(@cod, @msg) > 0 SET @rechazos += 1;
    IF @cod <> N'PAG_001'
    BEGIN
        SET @msg = NULL;
        BEGIN TRY
            INSERT INTO #w3mS2 EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = @ej, @idCorrelacion = @corr, @idGrupo = @gr;
        END TRY
        BEGIN CATCH
            SET @msg = ERROR_MESSAGE();
        END CATCH;
        IF @msg IS NOT NULL AND CHARINDEX(@cod, @msg) > 0 SET @rechazos += 1;
    END;
    FETCH NEXT FROM c INTO @n, @ej, @gr, @cod, @pg, @tm;
END;
CLOSE c;
DEALLOCATE c;
-- 4 casos x 2 SP + 2 casos de paginacion (solo la matriz) = 10 rechazos; ninguno devolvio filas
IF @rechazos <> 10 OR EXISTS (SELECT 1 FROM #w3mM2) OR EXISTS (SELECT 1 FROM #w3mS2)
    THROW 59331, 'TEST FAILED: W3M_AMB_01_RECHAZOS (otro docente SEC_002; grupo inexistente ERR_GRUPO_NO_EXISTE; coordinador y decano SEC_001; paginacion PAG_001)', 1;
DROP TABLE IF EXISTS #w3mM2, #w3mS2;
PRINT 'TEST_PASS:W3M_AMB_01_RECHAZOS';
GO

IF @@TRANCOUNT <> 0
    THROW 59332, 'TEST FAILED: W3M_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:W3M_TRANCOUNT_ZERO';
PRINT 'TEST PASS: test_w3m_matriz_asistencia';
GO
