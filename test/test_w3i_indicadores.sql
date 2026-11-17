USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CIERRE-W3I (docs/work-items/CIERRE-W3I-indicadores): los totales de los tableros por rol, el aforo y el nivel del semaforo se
-- resuelven en la base. Se amplian (columnas AL FINAL) usp_consultar_kpis_coordinador / _decano / _institucion y se agrega
-- usp_consultar_resumen_grupos_docente; usp_consultar_consolidado_asistencia_grupos_paginado, las revisiones de cancelacion y las
-- alertas del estudiante ganan el codigo de permanencia calculado con ufn_clasificar_permanencia.
--   W3I_COO_01_TOTALES        coordinador: docentes activos (mas de 100, sin los inactivos), estudiantes registrados y aforo del periodo
--   W3I_COO_02_SIN_PERIODO    coordinador sin grupos habilitados: totales de plantilla y padron, aforo en cero y tasa NULL
--   W3I_COO_03_AISLAMIENTO    el coordinador de otro programa no ve los numeros del programa A
--   W3I_DEC_01_TOTALES        decano: coordinadores activos, docentes sin repetir entre programas, aforo del periodo
--   W3I_DEC_02_AISLAMIENTO    el decano de otra facultad solo ve la suya
--   W3I_ADM_01_TOTALES        administrador: facultades (con decano inactivo cuentan), facultades activas, decanos y decanos activos
--   W3I_DOC_01_RESUMEN        docente titular: grupos habilitados, activos, cupo y ocupacion; un grupo de otro periodo no cuenta
--   W3I_DOC_02_AMBITO         otro docente recibe ceros y tasa NULL; coordinador y ejecutor nulo son rechazados
--   W3I_PER_01_CONSOLIDADO    codigoPermanencia del consolidado = ufn_clasificar_permanencia; cambiar el umbral del catalogo cambia el nivel
--   W3I_DIF_01_PERDIDA        PERDIDA por persona (KPI) frente a PERDIDA por matricula (consolidado): dos definiciones distintas, no un error
--   W3I_TRANCOUNT_ZERO
-- Fixtures por insercion directa dentro de una transaccion revertida (las cifras del seed se comparan por diferencia contra una
-- lectura previa); los rechazos van al final y fuera de ella porque los SP de consulta usan THROW.
PRINT 'TEST START: test_w3i_indicadores (CIERRE-W3I)';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
DECLARE @progA UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';
DECLARE @asigSeed UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
DECLARE @fac UNIQUEIDENTIFIER = (SELECT facultad FROM dbo.Programa WHERE id = @progA);
DECLARE @inst UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @fac);
DECLARE @coordA UNIQUEIDENTIFIER = (SELECT coordinador FROM dbo.Programa WHERE id = @progA);
DECLARE @uCA UNIQUEIDENTIFIER = (SELECT usuario FROM dbo.Coordinador WHERE id = @coordA);
DECLARE @uDec UNIQUEIDENTIFIER = (SELECT d.usuario FROM dbo.Facultad f JOIN dbo.Decano d ON d.id = f.decano WHERE f.id = @fac);
DECLARE @uAdm UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador WHERE institucion = @inst ORDER BY id);
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT tipoDePrograma FROM dbo.Programa WHERE id = @progA);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @estA IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL OR @tvCat IS NULL OR @uCA IS NULL OR @uDec IS NULL OR @uAdm IS NULL
    THROW 59400, 'TEST FAILED W3I: faltan fixtures del seed (tipo CC, estado A, toma manual cerrada, vinculacion CAT, coordinador, decano y administrador).', 1;

CREATE TABLE #w3iKc (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaPermanencia DECIMAL(5,2),
    sesionesProgramadas INT, sesionesVencidas INT, sesionesEjecutadas INT, sesionesVencidasSinRegistro INT, sesionesSinProcedenciaTemporal INT,
    porcentajeCumplimiento DECIMAL(5,2), porcentajeProgresoCalendario DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2),
    totalDocentes INT, gruposActivos INT, cupoTotal INT, matriculadosActivos INT, tasaAforo DECIMAL(7,2), estudiantesRegistrados INT);
CREATE TABLE #w3iKd (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
    sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
    gruposActivos INT, cupoTotal INT, matriculadosActivos INT, tasaAforo DECIMAL(7,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2),
    tomasDictadas INT, horasDictadas DECIMAL(12,6), horasFalta DECIMAL(12,6), totalCoordinadores INT, totalDocentes INT);
CREATE TABLE #w3iKi (idInstitucion UNIQUEIDENTIFIER, nombreInstitucion NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    totalFacultades INT, totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
    sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
    sesionesVencidas INT, sesionesConRegistro INT, porcentajeCumplimiento DECIMAL(5,2),
    estudiantesConMatriculaActiva INT, estudiantesRegistrados INT, docentesConGrupoActivo INT, docentesRegistrados INT,
    umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2), tomasDictadas INT, horasDictadas DECIMAL(12,6), horasFalta DECIMAL(12,6),
    totalDecanos INT, decanosActivos INT, facultadesActivas INT);
CREATE TABLE #w3iRg (gruposHabilitados INT, estudiantesActivos INT, cupoTotal INT, tasaOcupacion DECIMAL(7,2));
CREATE TABLE #w3iCo (idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
    nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
    estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
    porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT, totalRegistros INT,
    horasDictadas DECIMAL(12,2), porcentajeExcusa DECIMAL(5,2), porcentajeSinRegistro DECIMAL(5,2), codigoPermanencia NVARCHAR(10));

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
-- Lecturas previas (cifras del seed): los totales esperados son diferencias contra estas
DECLARE @bDocC INT, @bRegC INT, @bCoorD INT, @bDocD INT, @bFac INT, @bFacAct INT, @bDecano INT, @bDecAct INT;
INSERT INTO #w3iKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr, @idPrograma = @progA;
SELECT @bDocC = totalDocentes, @bRegC = estudiantesRegistrados FROM #w3iKc;
INSERT INTO #w3iKd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr;
SELECT @bCoorD = totalCoordinadores, @bDocD = totalDocentes FROM #w3iKd;
INSERT INTO #w3iKi EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr;
SELECT @bFac = totalFacultades, @bFacAct = facultadesActivas, @bDecano = totalDecanos, @bDecAct = decanosActivos FROM #w3iKi;
DELETE FROM #w3iKc; DELETE FROM #w3iKd; DELETE FROM #w3iKi;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @tag NVARCHAR(8) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 8);
    DECLARE @doc BIGINT = 940000000 + ABS(CHECKSUM(NEWID()) % 30000000);

    -- Personas: n identifica el rol; cada una con su Usuario
    CREATE TABLE #w3iP (k NVARCHAR(8) PRIMARY KEY, n INT, idUsuario UNIQUEIDENTIFIER, id UNIQUEIDENTIFIER);
    INSERT INTO #w3iP (k, n, idUsuario, id) VALUES
        (N'dG', 1, NEWID(), NEWID()), (N'dO', 2, NEWID(), NEWID()), (N'dA', 3, NEWID(), NEWID()), (N'dB', 4, NEWID(), NEWID()), (N'dC', 5, NEWID(), NEWID()),
        (N'dZ', 6, NEWID(), NEWID()), (N'cX', 7, NEWID(), NEWID()), (N'cI', 8, NEWID(), NEWID()), (N'c2', 9, NEWID(), NEWID()), (N'dec2', 10, NEWID(), NEWID()),
        (N'dec3', 11, NEWID(), NEWID()), (N's1', 12, NEWID(), NEWID()), (N's2', 13, NEWID(), NEWID()), (N's3', 14, NEWID(), NEWID()), (N'sZ', 15, NEWID(), NEWID());
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT p.idUsuario, @tipoCC, @doc + p.n, CONCAT(N'W3i', p.k), N'Ind', N'Per', N'W3i', CONCAT(N'w3i.', p.k, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_W3I'
    FROM #w3iP p;
    INSERT INTO dbo.Docente (id, usuario) SELECT id, idUsuario FROM #w3iP WHERE k IN (N'dG', N'dO', N'dA', N'dB', N'dC', N'dZ');
    INSERT INTO dbo.Estudiante (id, usuario) SELECT id, idUsuario FROM #w3iP WHERE k IN (N's1', N's2', N's3', N'sZ');
    INSERT INTO dbo.Coordinador (id, usuario, facultad) SELECT id, idUsuario, @fac FROM #w3iP WHERE k IN (N'cX', N'cI');
    UPDATE dbo.Coordinador SET estado = 0 WHERE id = (SELECT id FROM #w3iP WHERE k = N'cI');

    -- Segunda facultad F2 (decano propio, coordinador c2, programa P2) y tercera F3 con el decano inactivo
    DECLARE @f2 UNIQUEIDENTIFIER = NEWID(), @f3 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @progB UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) SELECT id, idUsuario FROM #w3iP WHERE k IN (N'dec2', N'dec3');
    UPDATE dbo.Decano SET estado = 0 WHERE id = (SELECT id FROM #w3iP WHERE k = N'dec3');
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES
        (@f2, N'W3I Facultad dos', @inst, (SELECT id FROM #w3iP WHERE k = N'dec2'), 1),
        (@f3, N'W3I Facultad tres', @inst, (SELECT id FROM #w3iP WHERE k = N'dec3'), 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) SELECT id, idUsuario, @f2 FROM #w3iP WHERE k = N'c2';
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p2, @f2, @tipoProg, N'W3I Programa dos', (SELECT id FROM #w3iP WHERE k = N'c2'), 1),
        (@progB, @fac, @tipoProg, N'W3I Programa B', @coordA, 1);

    -- Plantilla del programa A: dA y dB activos (dB tambien en el programa B de la misma facultad), dC inactivo y 120 mas (> 100)
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    SELECT NEWID(), p.id, @progA, @tvCat, IIF(p.k = N'dC', 0, 1), SYSUTCDATETIME() FROM #w3iP p WHERE p.k IN (N'dA', N'dB', N'dC');
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    SELECT NEWID(), p.id, @progB, @tvCat, 1, SYSUTCDATETIME() FROM #w3iP p WHERE p.k = N'dB';
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    SELECT NEWID(), p.id, @p2, @tvCat, 1, SYSUTCDATETIME() FROM #w3iP p WHERE p.k = N'dZ';
    CREATE TABLE #w3iBulk (n INT PRIMARY KEY, idUsuario UNIQUEIDENTIFIER, id UNIQUEIDENTIFIER);
    INSERT INTO #w3iBulk (n, idUsuario, id)
    SELECT TOP (120) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), NEWID(), NEWID() FROM sys.all_objects a CROSS JOIN (SELECT TOP 2 1 x FROM sys.all_objects) b;
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT b.idUsuario, @tipoCC, @doc + 1000 + b.n, CONCAT(N'W3iBulk', b.n), N'Ind', N'Doc', N'W3i', CONCAT(N'w3i.bulk', b.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_W3I'
    FROM #w3iBulk b;
    INSERT INTO dbo.Docente (id, usuario) SELECT id, idUsuario FROM #w3iBulk;
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    SELECT NEWID(), b.id, @progA, @tvCat, 1, SYSUTCDATETIME() FROM #w3iBulk b;

    -- Padron: s1, s2 y s3 en el programa A; sZ en el programa P2
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
    SELECT NEWID(), p.id, IIF(p.k = N'sZ', @p2, @progA) FROM #w3iP p WHERE p.k IN (N's1', N's2', N's3', N'sZ');

    -- Periodo vigente PW (el mas reciente: arranca hoy) y periodo pasado PO; grupos G1 y G2 en PW y G3 en PO, todos del docente dG
    DECLARE @pw UNIQUEIDENTIFIER = NEWID(), @po UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (@pw, @inst, N'W3I vigente', 3500000 + ABS(CHECKSUM(NEWID()) % 400000), @hoy, DATEADD(DAY, 40, @hoy), YEAR(@hoy)),
        (@po, @inst, N'W3I pasado', 3900000 + ABS(CHECKSUM(NEWID()) % 90000), DATEADD(YEAR, -3, @hoy), DATEADD(YEAR, -2, @hoy), YEAR(@hoy) - 3);
    DECLARE @dG UNIQUEIDENTIFIER = (SELECT id FROM #w3iP WHERE k = N'dG'), @dO UNIQUEIDENTIFIER = (SELECT id FROM #w3iP WHERE k = N'dO');
    DECLARE @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID(), @g3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente) VALUES
        (@g1, @asigSeed, @pw, 961000 + ABS(CHECKSUM(NEWID()) % 9000), N'W3I G1', 30, 0, 0, 0, @dG),
        (@g2, @asigSeed, @pw, 971000 + ABS(CHECKSUM(NEWID()) % 9000), N'W3I G2', 20, 0, 0, 0, @dG),
        (@g3, @asigSeed, @po, 981000 + ABS(CHECKSUM(NEWID()) % 9000), N'W3I G3', 40, 0, 0, 0, @dG);
    -- G1: s1, s2 y s3 activos; G2: s1 activo; G3: s2 activo (no cuenta: periodo pasado)
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT NEWID(), @estA, p.id, v.g FROM #w3iP p INNER JOIN (VALUES (N's1', @g1), (N's2', @g1), (N's3', @g1), (N's1', @g2), (N's2', @g3)) v(k, g) ON v.k = p.k;

    -- Sesiones: s1 falta a toda la sesion de G1 y a toda la de G2 (PERDIDA en dos grupos); s2 y s3 asisten a la de G1
    DECLARE @sesG1 UNIQUEIDENTIFIER = NEWID(), @sesG2 UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal) VALUES
        (@sesG1, N'W3I S1', 1, CONCAT(N'W3I1', @tag), 1, @g1, DATEADD(HOUR, -5, SYSUTCDATETIME()), DATEADD(HOUR, -3, SYSUTCDATETIME()), N'UTC_V2'),
        (@sesG2, N'W3I S2', 1, CONCAT(N'W3I2', @tag), 1, @g2, DATEADD(HOUR, -5, SYSUTCDATETIME()), DATEADD(HOUR, -3, SYSUTCDATETIME()), N'UTC_V2');
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), se.id, 1, @modoManual, @estCerrada, 0, @dG, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM dbo.Sesion se WHERE se.id IN (@sesG1, @sesG2);
    CREATE TABLE #w3iD (sesion UNIQUEIDENTIFIER, grupo UNIQUEIDENTIFIER, est NVARCHAR(8), codigo NVARCHAR(5));
    INSERT INTO #w3iD VALUES (@sesG1, @g1, N's1', N'SJC'), (@sesG1, @g1, N's2', N'AN'), (@sesG1, @g1, N's3', N'AN'), (@sesG2, @g2, N's1', N'SJC');
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), eg.id, d.sesion FROM #w3iD d INNER JOIN #w3iP p ON p.k = d.est INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = p.id AND eg.grupo = d.grupo;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(d.codigo = N'AN', 1, 0), rc.id, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM #w3iD d INNER JOIN dbo.Sesion se ON se.id = d.sesion INNER JOIN #w3iP p ON p.k = d.est
    INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = p.id AND eg.grupo = d.grupo
    INNER JOIN dbo.Asistencia a ON a.estudianteGrupo = eg.id AND a.sesion = d.sesion
    INNER JOIN dbo.TomaAsistencia t ON t.sesion = d.sesion AND t.numero = 1
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = d.codigo;

    DECLARE @uC2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #w3iP WHERE k = N'c2'), @uDec2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #w3iP WHERE k = N'dec2');
    DECLARE @uDG UNIQUEIDENTIFIER = (SELECT idUsuario FROM #w3iP WHERE k = N'dG'), @uDO UNIQUEIDENTIFIER = (SELECT idUsuario FROM #w3iP WHERE k = N'dO');
    DECLARE @n INT;

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_COO_01: coordinador del programa A con el periodo vigente PW
    -- ---------------------------------------------------------------------------------------------------------------
    INSERT INTO #w3iKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr, @idPrograma = @progA, @idPeriodoAcademico = @pw;
    -- Docentes: dA, dB y los 120 (dC esta inactivo y no cuenta); estudiantes registrados: s1, s2 y s3 (la matricula no es el padron)
    IF NOT EXISTS (SELECT 1 FROM #w3iKc WHERE totalDocentes = @bDocC + 122 AND estudiantesRegistrados = @bRegC + 3)
        THROW 59401, 'TEST FAILED W3I_COO_01_TOTALES: totalDocentes debe sumar los docentes activos sin tope de pagina (122, sin el inactivo) y estudiantesRegistrados el padron del programa (3).', 1;
    IF NOT EXISTS (SELECT 1 FROM #w3iKc WHERE gruposActivos = 2 AND cupoTotal = 50 AND matriculadosActivos = 4 AND tasaAforo = 8.00)
        THROW 59402, 'TEST FAILED W3I_COO_01_TOTALES: el aforo del periodo vigente debe ser 4 / 50 = 8.00 con 2 grupos (el grupo del periodo pasado no cuenta).', 1;
    PRINT 'TEST_PASS:W3I_COO_01_TOTALES';

    -- Sin periodo explicito se resuelve el vigente mas reciente con grupos habilitados del programa
    DELETE FROM #w3iKc;
    INSERT INTO #w3iKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #w3iKc WHERE idPeriodoAcademico = @pw AND nombrePeriodoAcademico = N'W3I vigente' AND gruposActivos = 2)
        THROW 59403, 'TEST FAILED W3I_COO_01_TOTALES: sin periodo explicito debe resolver el periodo vigente con el nombre para mostrarlo.', 1;

    -- W3I_COO_02: coordinador sin grupos habilitados (c2 con el programa P2)
    DELETE FROM #w3iKc;
    INSERT INTO #w3iKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC2, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #w3iKc WHERE idPrograma = @p2 AND idPeriodoAcademico IS NULL AND nombrePeriodoAcademico IS NULL
                                           AND gruposActivos = 0 AND cupoTotal = 0 AND matriculadosActivos = 0 AND tasaAforo IS NULL
                                           AND totalDocentes = 1 AND estudiantesRegistrados = 1)
        THROW 59404, 'TEST FAILED W3I_COO_02_SIN_PERIODO: sin periodo vigente: aforo en cero, tasa NULL, sin nombre de periodo y con la plantilla (1) y el padron (1) del programa.', 1;
    PRINT 'TEST_PASS:W3I_COO_02_SIN_PERIODO';

    -- W3I_COO_03: el coordinador de P2 no ve los 122 docentes ni el aforo del programa A, aunque pida el periodo PW
    DELETE FROM #w3iKc;
    INSERT INTO #w3iKc EXEC dbo.usp_consultar_kpis_coordinador @idUsuarioEjecutor = @uC2, @idCorrelacion = @corr, @idPeriodoAcademico = @pw;
    IF NOT EXISTS (SELECT 1 FROM #w3iKc WHERE idPrograma = @p2 AND totalDocentes = 1 AND estudiantesRegistrados = 1 AND gruposActivos = 0 AND cupoTotal = 0)
        THROW 59405, 'TEST FAILED W3I_COO_03_AISLAMIENTO: el coordinador de otro programa solo ve los numeros de su programa.', 1;
    PRINT 'TEST_PASS:W3I_COO_03_AISLAMIENTO';

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_DEC_01: decano de la facultad con los programas A y B (dB cuenta una sola vez; cX activo, cI inactivo)
    -- ---------------------------------------------------------------------------------------------------------------
    INSERT INTO #w3iKd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @pw;
    IF NOT EXISTS (SELECT 1 FROM #w3iKd WHERE totalDocentes = @bDocD + 122 AND totalCoordinadores = @bCoorD + 1)
        THROW 59406, 'TEST FAILED W3I_DEC_01_TOTALES: totalDocentes cuenta una vez al docente de dos programas (122 nuevos) y totalCoordinadores solo al coordinador activo (+1).', 1;
    IF NOT EXISTS (SELECT 1 FROM #w3iKd WHERE gruposActivos = 2 AND cupoTotal = 50 AND matriculadosActivos = 4 AND tasaAforo = 8.00)
        THROW 59407, 'TEST FAILED W3I_DEC_01_TOTALES: el aforo de la facultad en el periodo vigente debe ser 4 / 50 = 8.00 con 2 grupos.', 1;
    PRINT 'TEST_PASS:W3I_DEC_01_TOTALES';

    -- W3I_DEC_02: el decano de F2 solo ve su facultad (1 coordinador, 1 docente, sin grupos)
    DELETE FROM #w3iKd;
    INSERT INTO #w3iKd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec2, @idCorrelacion = @corr, @idPeriodoAcademico = @pw;
    IF NOT EXISTS (SELECT 1 FROM #w3iKd WHERE idFacultad = @f2 AND totalDocentes = 1 AND totalCoordinadores = 1 AND gruposActivos = 0 AND cupoTotal = 0 AND tasaAforo IS NULL)
        THROW 59408, 'TEST FAILED W3I_DEC_02_AISLAMIENTO: el decano de otra facultad solo ve los numeros de la suya.', 1;
    PRINT 'TEST_PASS:W3I_DEC_02_AISLAMIENTO';

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_ADM_01: administrador: F2 y F3 suman facultades aunque el decano de F3 este inactivo
    -- ---------------------------------------------------------------------------------------------------------------
    INSERT INTO #w3iKi EXEC dbo.usp_consultar_kpis_institucion @idUsuarioEjecutor = @uAdm, @idCorrelacion = @corr, @idPeriodoAcademico = @pw;
    IF NOT EXISTS (SELECT 1 FROM #w3iKi WHERE totalFacultades = @bFac + 2 AND facultadesActivas = @bFacAct + 2 AND totalDecanos = @bDecano + 2 AND decanosActivos = @bDecAct + 1)
        THROW 59409, 'TEST FAILED W3I_ADM_01_TOTALES: dos facultades nuevas (una con decano inactivo) suman 2 facultades, 2 activas, 2 decanos y 1 decano activo.', 1;
    PRINT 'TEST_PASS:W3I_ADM_01_TOTALES';

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_DOC_01: resumen de grupos del docente titular (G1 y G2 de PW; G3 es de un periodo pasado)
    -- ---------------------------------------------------------------------------------------------------------------
    INSERT INTO #w3iRg EXEC dbo.usp_consultar_resumen_grupos_docente @idUsuarioEjecutor = @uDG, @idCorrelacion = @corr;
    IF (SELECT COUNT(1) FROM #w3iRg) <> 1
       OR NOT EXISTS (SELECT 1 FROM #w3iRg WHERE gruposHabilitados = 2 AND estudiantesActivos = 4 AND cupoTotal = 50 AND tasaOcupacion = 8.00)
        THROW 59410, 'TEST FAILED W3I_DOC_01_RESUMEN: una fila con 2 grupos habilitados, 4 estudiantes activos, cupo 50 y ocupacion 8.00.', 1;
    PRINT 'TEST_PASS:W3I_DOC_01_RESUMEN';

    -- W3I_DOC_02: otro docente (sin grupos) recibe ceros y tasa NULL
    DELETE FROM #w3iRg;
    INSERT INTO #w3iRg EXEC dbo.usp_consultar_resumen_grupos_docente @idUsuarioEjecutor = @uDO, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #w3iRg WHERE gruposHabilitados = 0 AND estudiantesActivos = 0 AND cupoTotal = 0 AND tasaOcupacion IS NULL)
        THROW 59411, 'TEST FAILED W3I_DOC_02_AMBITO: un docente sin grupos debe recibir ceros y tasa NULL, no los grupos de otro.', 1;

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_PER_01: consolidado del programa A en PW. El grupo G1 tiene 6 h-estudiante dictadas (2 h x 3) y 2 h de falta (s1): 33.33 %
    -- ---------------------------------------------------------------------------------------------------------------
    INSERT INTO #w3iCo EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @pw, @idPrograma = @progA;
    IF (SELECT COUNT(1) FROM #w3iCo) <> 2
       OR NOT EXISTS (SELECT 1 FROM #w3iCo WHERE idGrupo = @g1 AND porcentajeInasistencia = 33.33 AND codigoPermanencia = N'PERDIDA')
       OR NOT EXISTS (SELECT 1 FROM #w3iCo WHERE idGrupo = @g2 AND porcentajeInasistencia = 100.00 AND codigoPermanencia = N'PERDIDA')
       OR EXISTS (SELECT 1 FROM #w3iCo WHERE codigoPermanencia IS NULL OR codigoPermanencia <> dbo.ufn_clasificar_permanencia(porcentajeInasistencia, NULL))
        THROW 59412, 'TEST FAILED W3I_PER_01_CONSOLIDADO: con umbrales 15/20 el grupo al 33.33 % y el del 100 % son PERDIDA y coinciden con ufn_clasificar_permanencia.', 1;
    -- Un cambio de parametro del catalogo cambia el nivel (los umbrales no estan quemados): 30/40 -> RIESGO; 40/60 -> REGULAR
    UPDATE dbo.CatalogoParametro SET valor = N'30' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'40' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #w3iCo;
    INSERT INTO #w3iCo EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @pw, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #w3iCo WHERE idGrupo = @g1 AND codigoPermanencia = N'RIESGO')
       OR NOT EXISTS (SELECT 1 FROM #w3iCo WHERE idGrupo = @g2 AND codigoPermanencia = N'PERDIDA')
        THROW 59413, 'TEST FAILED W3I_PER_01_CONSOLIDADO: con umbrales 30/40 el grupo al 33.33 % debe ser RIESGO y el del 100 % PERDIDA.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'40' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'60' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #w3iCo;
    INSERT INTO #w3iCo EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @pw, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #w3iCo WHERE idGrupo = @g1 AND codigoPermanencia = N'REGULAR')
        THROW 59414, 'TEST FAILED W3I_PER_01_CONSOLIDADO: con umbrales 40/60 el grupo al 33.33 % debe ser REGULAR.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'15' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'20' WHERE grupo = N'ASISTENCIA' AND clave = N'UMBRAL_ALERTA_PERDIDA';
    PRINT 'TEST_PASS:W3I_PER_01_CONSOLIDADO';

    -- ---------------------------------------------------------------------------------------------------------------
    -- W3I_DIF_01: s1 pierde en dos grupos. El KPI cuenta PERSONAS (1) y el consolidado MATRICULAS (2): son definiciones distintas
    -- ---------------------------------------------------------------------------------------------------------------
    DELETE FROM #w3iKd;
    INSERT INTO #w3iKd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr, @idPeriodoAcademico = @pw;
    DELETE FROM #w3iCo;
    INSERT INTO #w3iCo EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idPeriodoAcademico = @pw;
    SELECT @n = SUM(estudiantesPerdida) FROM #w3iCo WHERE idGrupo IN (@g1, @g2);
    IF @n <> 2 OR NOT EXISTS (SELECT 1 FROM #w3iKd WHERE estudiantesPerdida = 1 AND totalEstudiantes = 3)
        THROW 59415, 'TEST FAILED W3I_DIF_01_PERDIDA: el consolidado suma 2 matriculas en PERDIDA (s1 en G1 y G2) y el KPI cuenta 1 persona de 3.', 1;
    PRINT 'TEST_PASS:W3I_DIF_01_PERDIDA';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(2048) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    THROW 59499, @err, 1;
END CATCH;
DROP TABLE IF EXISTS #w3iKc, #w3iKd, #w3iKi, #w3iRg, #w3iCo;
GO

-- W3I_DOC_02: rechazos con el seed (fuera de transaccion): coordinador SEC_001 y ejecutor nulo VAL_001
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @msg NVARCHAR(4000), @rechazos INT = 0;
DECLARE @userCoord UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER;
SELECT TOP 1 @userCoord = idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1 AND estaActivoRolCoordinador = 1 ORDER BY id;
SELECT TOP 1 @userT = d.usuario FROM dbo.Docente d INNER JOIN dbo.Grupo g ON g.docente = d.id ORDER BY d.id;
IF @userCoord IS NULL OR @userT IS NULL
    THROW 59420, 'TEST FAILED W3I_DOC_02: faltan fixtures del seed (coordinador y docente con grupos).', 1;
CREATE TABLE #w3iR2 (gruposHabilitados INT, estudiantesActivos INT, cupoTotal INT, tasaOcupacion DECIMAL(7,2));
DECLARE @casos TABLE (n INT, ejecutor UNIQUEIDENTIFIER, codigo NVARCHAR(30));
INSERT INTO @casos VALUES (1, @userCoord, N'SEC_001'), (2, NULL, N'VAL_001');
DECLARE @n INT, @ej UNIQUEIDENTIFIER, @cod NVARCHAR(30);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT n, ejecutor, codigo FROM @casos ORDER BY n;
OPEN c;
FETCH NEXT FROM c INTO @n, @ej, @cod;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @msg = NULL;
    BEGIN TRY
        INSERT INTO #w3iR2 EXEC dbo.usp_consultar_resumen_grupos_docente @idUsuarioEjecutor = @ej, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
    END CATCH;
    IF @msg IS NOT NULL AND CHARINDEX(@cod, @msg) > 0 SET @rechazos += 1;
    FETCH NEXT FROM c INTO @n, @ej, @cod;
END;
CLOSE c;
DEALLOCATE c;
IF @rechazos <> 2 OR EXISTS (SELECT 1 FROM #w3iR2)
    THROW 59421, 'TEST FAILED: W3I_DOC_02_AMBITO (coordinador SEC_001; ejecutor nulo VAL_001; sin filas)', 1;
DROP TABLE IF EXISTS #w3iR2;
PRINT 'TEST_PASS:W3I_DOC_02_AMBITO';
GO

IF @@TRANCOUNT <> 0
    THROW 59422, 'TEST FAILED: W3I_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:W3I_TRANCOUNT_ZERO';
PRINT 'TEST PASS: test_w3i_indicadores';
GO
