USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_hu018_hu019_plan_horas_estudiante (HU018, HU019)';
PRINT '==================================================';

-- HU018: usp_consultar_plan_estudio_estudiante (estructura curricular por semestres del propio estudiante).
-- HU019: usp_consultar_horas_programadas_estudiante (horas programadas de sus materias inscritas).
--   HU018_PLAN_ESTRUCTURA_ORDEN   semestres y asignaturas de los planes activos de sus programas, en orden; semestre vacio
--   HU018_PLAN_EXCLUSIONES        sin plan inactivo, vinculo inactivo, asignatura inactiva ni plan de otro programa
--   HU018_PLAN_CURSANDO           cursando solo con matricula inscrita, con el grupo que cursa
--   HU018_PLAN_PRIVACIDAD         otro estudiante ve solo su plan; quien no es estudiante, 0 filas; ejecutor nulo => VAL_001
--   HU018_PLAN_COLUMNAS           18 columnas con el nombre y el orden que lee el backend
--   HU019_HORAS_PROGRAMADAS       sesiones no canceladas (dictadas o por dictar); grupo sin sesiones => 0; solo inscritas
--   HU019_HORAS_VALIDACIONES      quien no es estudiante, 0 filas; ejecutor nulo => VAL_001; 4 columnas

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @tipoId        UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @tipoProg      UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
DECLARE @sem1          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Semestre WHERE numero = 1);
DECLARE @sem2          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Semestre WHERE numero = 2);
DECLARE @sem3          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Semestre WHERE numero = 3);
DECLARE @area          UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura);
DECLARE @compESP       UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @carOBL        UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OBL');
DECLARE @carOPT        UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OPT');
DECLARE @estA          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @estI          UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I');
DECLARE @tipoManual    UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
IF @idInstitucion IS NULL OR @tipoId IS NULL OR @tipoProg IS NULL OR @sem1 IS NULL OR @sem2 IS NULL OR @sem3 IS NULL OR @area IS NULL
   OR @compESP IS NULL OR @carOBL IS NULL OR @carOPT IS NULL OR @estA IS NULL OR @estI IS NULL OR @tipoManual IS NULL
    THROW 54600, 'TEST FAILED: fixtures base no disponibles.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    -- La matricula inscrita es la del parametro; el fixture usa su valor por defecto, independiente del ambiente.
    UPDATE dbo.CatalogoParametro SET valor = N'A' WHERE grupo = 'MATRICULA' AND clave = 'ESTADO_INSCRITA';

    CREATE TABLE #u (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    DECLARE @i INT = 1;
    WHILE @i <= 6
    BEGIN
        DECLARE @uid UNIQUEIDENTIFIER = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uid, @tipoId, 340000000 + ABS(CHECKSUM(NEWID()) % 99999999), CONCAT(N'Apellido', CHAR(64 + @i)), N'QA', CONCAT(N'Nombre', CHAR(64 + @i)), N'X',
                CONCAT(CONVERT(NVARCHAR(36), @uid), N'@qa.test'), 1, 1, N'x');
        INSERT INTO #u (id) VALUES (@uid);
        SET @i += 1;
    END
    -- n: 1 decano, 2 coordinador P1, 3 coordinador P2, 4 docente, 5 estudiante E1 (P1), 6 estudiante E2 (P2)
    DECLARE @uDoc UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 4), @uE1 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 5),
            @uE2 UNIQUEIDENTIFIER = (SELECT id FROM #u WHERE n = 6);

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @dec UNIQUEIDENTIFIER = NEWID(), @f UNIQUEIDENTIFIER = NEWID(), @c1 UNIQUEIDENTIFIER = NEWID(), @c2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @doc UNIQUEIDENTIFIER = NEWID();
    DECLARE @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@dec, (SELECT id FROM #u WHERE n = 1));
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f, CONCAT(N'QA HU018 ', @sufijo), @idInstitucion, @dec, 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES (@c1, (SELECT id FROM #u WHERE n = 2), @f), (@c2, (SELECT id FROM #u WHERE n = 3), @f);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (@p1, @f, @tipoProg, CONCAT(N'HU018 P1 ', @sufijo), @c1, 1), (@p2, @f, @tipoProg, CONCAT(N'HU018 P2 ', @sufijo), @c2, 1);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@doc, @uDoc);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @uE1), (@e2, @uE2);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @e1, @p1), (NEWID(), @e2, @p2);

    -- Planes: PL1 activo de P1 (semestres 1, 2 y 3; el 3 sin asignaturas), PLX inactivo de P1, PL2 activo de P2.
    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @plx UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @inp1 INT = 960000 + ABS(CHECKSUM(NEWID()) % 9000);
    DECLARE @s11 UNIQUEIDENTIFIER = NEWID(), @s12 UNIQUEIDENTIFIER = NEWID(), @s13 UNIQUEIDENTIFIER = NEWID(), @sx1 UNIQUEIDENTIFIER = NEWID(), @s21 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, @inp1, 1), (@plx, @p1, @inp1 + 9000, 0), (@pl2, @p2, @inp1 + 18000, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES
        (@s11, @pl1, @sem1), (@s12, @pl1, @sem2), (@s13, @pl1, @sem3), (@sx1, @plx, @sem1), (@s21, @pl2, @sem1);

    -- Asignaturas: A1 obligatoria y A2 optativa en el semestre 1 (el orden pone la obligatoria primero aunque su nombre vaya
    -- despues en el alfabeto); A3 en el semestre 2; A4 inactiva; A5 del otro programa; A6 con el vinculo desvinculado.
    DECLARE @a1 UNIQUEIDENTIFIER = NEWID(), @a2 UNIQUEIDENTIFIER = NEWID(), @a3 UNIQUEIDENTIFIER = NEWID(), @a4 UNIQUEIDENTIFIER = NEWID(),
            @a5 UNIQUEIDENTIFIER = NEWID(), @a6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado) VALUES
        (@a1, CONCAT(N'P1', @sufijo), CONCAT(N'Zoologia QA018 ', @sufijo), 3, @area, @compESP, 1),
        (@a2, CONCAT(N'P2', @sufijo), CONCAT(N'Algebra QA018 ', @sufijo), 4, @area, @compESP, 1),
        (@a3, CONCAT(N'P3', @sufijo), CONCAT(N'Fisica QA018 ', @sufijo), 2, @area, @compESP, 1),
        (@a4, CONCAT(N'P4', @sufijo), CONCAT(N'Inactiva QA018 ', @sufijo), 3, @area, @compESP, 0),
        (@a5, CONCAT(N'P5', @sufijo), CONCAT(N'Ajena QA018 ', @sufijo), 5, @area, @compESP, 1),
        (@a6, CONCAT(N'P6', @sufijo), CONCAT(N'Desvinculada QA018 ', @sufijo), 3, @area, @compESP, 1);
    INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc) VALUES
        (NEWID(), @a1, @s11, @carOBL, 1, '2000-01-01', NULL),
        (NEWID(), @a2, @s11, @carOPT, 1, '2000-01-01', NULL),
        (NEWID(), @a3, @s12, @carOBL, 1, '2000-01-01', NULL),
        (NEWID(), @a4, @s12, @carOBL, 1, '2000-01-01', NULL),
        (NEWID(), @a6, @s12, @carOBL, 0, '2000-01-01', '2001-01-01'),
        (NEWID(), @a1, @sx1, @carOBL, 1, '2000-01-01', NULL),
        (NEWID(), @a5, @s21, @carOBL, 1, '2000-01-01', NULL);

    -- Grupos del periodo vigente: G1 (A1), G2 (A2), G3 (A3), G5 (A5).
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @per UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (@per, @idInstitucion, CONCAT(N'QA18 ', @sufijo), 960000 + ABS(CHECKSUM(NEWID()) % 9999), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    DECLARE @base INT = 800000 + ABS(CHECKSUM(NEWID()) % 9000) * 10;
    DECLARE @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID(), @g3 UNIQUEIDENTIFIER = NEWID(), @g5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente) VALUES
        (@g1, @a1, @per, @base + 1, N'Grupo QA18 G1', 30, 0, 0, 0, @doc), (@g2, @a2, @per, @base + 2, N'Grupo QA18 G2', 30, 0, 0, 0, @doc),
        (@g3, @a3, @per, @base + 3, N'Grupo QA18 G3', 30, 0, 0, 0, @doc), (@g5, @a5, @per, @base + 5, N'Grupo QA18 G5', 30, 0, 0, 0, @doc);
    -- E1: inscrito en G1 y G3, retirado (I) de G2. E2: inscrito en G5.
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES
        (NEWID(), @estA, @e1, @g1), (NEWID(), @estI, @e1, @g2), (NEWID(), @estA, @e1, @g3), (NEWID(), @estA, @e2, @g5);

    -- Sesiones de G1: dos dictadas y una por dictar (2 h cada una) y una cuarta cancelada. G2: una sesion (E1 no esta inscrito).
    -- G3: sin sesiones.
    DECLARE @sc UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal) VALUES
        (NEWID(), N'QA18 S1', 1, CONCAT(N'Q18A', @sufijo), 1, @g1, DATEADD(HOUR, -2, DATEADD(DAY, -10, SYSUTCDATETIME())), DATEADD(DAY, -10, SYSUTCDATETIME()), N'UTC_V2'),
        (NEWID(), N'QA18 S2', 2, CONCAT(N'Q18B', @sufijo), 2, @g1, DATEADD(HOUR, -2, DATEADD(DAY, -3, SYSUTCDATETIME())), DATEADD(DAY, -3, SYSUTCDATETIME()), N'UTC_V2'),
        (NEWID(), N'QA18 S3', 3, CONCAT(N'Q18C', @sufijo), 3, @g1, DATEADD(DAY, 4, SYSUTCDATETIME()), DATEADD(HOUR, 2, DATEADD(DAY, 4, SYSUTCDATETIME())), N'UTC_V2'),
        (@sc,     N'QA18 S4', 4, CONCAT(N'Q18D', @sufijo), 4, @g1, DATEADD(DAY, 11, SYSUTCDATETIME()), DATEADD(HOUR, 2, DATEADD(DAY, 11, SYSUTCDATETIME())), N'UTC_V2'),
        (NEWID(), N'QA18 S5', 1, CONCAT(N'Q18E', @sufijo), 1, @g2, DATEADD(HOUR, -2, DATEADD(DAY, -3, SYSUTCDATETIME())), DATEADD(DAY, -3, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    VALUES (@sc, @tipoManual, N'QA18 cancelada', NULL, @uDoc, NEWID());

    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000);
    CREATE TABLE #p (n INT IDENTITY(1,1), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT,
        idSemestrePlanEstudio UNIQUEIDENTIFIER, numeroSemestre INT, idAsignaturaPlanEstudio UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER,
        codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100), creditos INT, codigoComponente NVARCHAR(3), nombreComponente NVARCHAR(100),
        codigoCaracter NVARCHAR(3), nombreCaracter NVARCHAR(50), cursando BIT, idGrupoCursando UNIQUEIDENTIFIER, nombreGrupoCursando NVARCHAR(100));
    CREATE TABLE #h (n INT IDENTITY(1,1), idEstudianteGrupo UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, sesionesProgramadas INT, horasProgramadas DECIMAL(12,6));

    -- PE-01: estructura y orden. E1 ve el plan activo de P1: semestre 1 (obligatoria antes que optativa), semestre 2 y el
    --        semestre 3 vacio (una fila sin asignatura).
    INSERT INTO #p (idPrograma, nombrePrograma, idPlanEstudio, inpPlanEstudio, idSemestrePlanEstudio, numeroSemestre, idAsignaturaPlanEstudio, idAsignatura,
        codigoAsignatura, nombreAsignatura, creditos, codigoComponente, nombreComponente, codigoCaracter, nombreCaracter, cursando, idGrupoCursando, nombreGrupoCursando)
    EXEC dbo.usp_consultar_plan_estudio_estudiante @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #p) <> 4
        THROW 54601, 'TEST FAILED: PE-01 se esperaban 4 filas (A1, A2, A3 y el semestre 3 vacio).', 1;
    IF (SELECT idAsignatura FROM #p WHERE n = 1) <> @a1 OR (SELECT idAsignatura FROM #p WHERE n = 2) <> @a2
       OR (SELECT idAsignatura FROM #p WHERE n = 3) <> @a3 OR (SELECT idAsignatura FROM #p WHERE n = 4) IS NOT NULL
        THROW 54602, 'TEST FAILED: PE-01 orden por semestre, caracter y nombre.', 1;
    IF NOT EXISTS (SELECT 1 FROM #p WHERE n = 1 AND idPrograma = @p1 AND idPlanEstudio = @pl1 AND inpPlanEstudio = @inp1 AND numeroSemestre = 1
                   AND idSemestrePlanEstudio = @s11 AND creditos = 3 AND codigoCaracter = N'OBL' AND nombreCaracter = N'Obligatoria'
                   AND codigoComponente = N'ESP' AND codigoAsignatura = CONCAT(N'P1', @sufijo) AND nombrePrograma = CONCAT(N'HU018 P1 ', @sufijo))
       OR NOT EXISTS (SELECT 1 FROM #p WHERE n = 2 AND numeroSemestre = 1 AND creditos = 4 AND codigoCaracter = N'OPT')
       OR NOT EXISTS (SELECT 1 FROM #p WHERE n = 3 AND numeroSemestre = 2 AND idSemestrePlanEstudio = @s12 AND creditos = 2)
        THROW 54603, 'TEST FAILED: PE-01 datos del plan, del semestre o de la asignatura.', 1;
    IF NOT EXISTS (SELECT 1 FROM #p WHERE n = 4 AND numeroSemestre = 3 AND idSemestrePlanEstudio = @s13 AND idPlanEstudio = @pl1
                   AND idAsignaturaPlanEstudio IS NULL AND codigoAsignatura IS NULL AND creditos IS NULL AND codigoCaracter IS NULL
                   AND cursando = 0 AND idGrupoCursando IS NULL)
        THROW 54604, 'TEST FAILED: PE-01 el semestre sin asignaturas debe salir en una fila sin asignatura.', 1;
    PRINT 'TEST_PASS:HU018_PLAN_ESTRUCTURA_ORDEN';

    -- PE-02: no aparecen el plan inactivo, la asignatura inactiva, el vinculo desvinculado ni el plan de otro programa.
    IF EXISTS (SELECT 1 FROM #p WHERE idPlanEstudio IN (@plx, @pl2) OR idAsignatura IN (@a4, @a5, @a6))
        THROW 54605, 'TEST FAILED: PE-02 aparecio un plan inactivo o ajeno, una asignatura inactiva o un vinculo desvinculado.', 1;
    PRINT 'TEST_PASS:HU018_PLAN_EXCLUSIONES';

    -- PE-03: cursando solo con matricula inscrita. A1 (G1) y A3 (G3) si; A2 no, porque la matricula en G2 no esta inscrita.
    IF NOT EXISTS (SELECT 1 FROM #p WHERE idAsignatura = @a1 AND cursando = 1 AND idGrupoCursando = @g1 AND nombreGrupoCursando = N'Grupo QA18 G1')
       OR NOT EXISTS (SELECT 1 FROM #p WHERE idAsignatura = @a3 AND cursando = 1 AND idGrupoCursando = @g3)
       OR NOT EXISTS (SELECT 1 FROM #p WHERE idAsignatura = @a2 AND cursando = 0 AND idGrupoCursando IS NULL AND nombreGrupoCursando IS NULL)
        THROW 54606, 'TEST FAILED: PE-03 cursando debe salir solo de la matricula inscrita.', 1;
    PRINT 'TEST_PASS:HU018_PLAN_CURSANDO';

    -- PE-04: privacidad. E2 ve solo el plan de su programa; quien no es estudiante no ve nada; ejecutor nulo => VAL_001.
    TRUNCATE TABLE #p;
    INSERT INTO #p (idPrograma, nombrePrograma, idPlanEstudio, inpPlanEstudio, idSemestrePlanEstudio, numeroSemestre, idAsignaturaPlanEstudio, idAsignatura,
        codigoAsignatura, nombreAsignatura, creditos, codigoComponente, nombreComponente, codigoCaracter, nombreCaracter, cursando, idGrupoCursando, nombreGrupoCursando)
    EXEC dbo.usp_consultar_plan_estudio_estudiante @idUsuarioEjecutor = @uE2, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #p) <> 1
       OR NOT EXISTS (SELECT 1 FROM #p WHERE idPlanEstudio = @pl2 AND idAsignatura = @a5 AND creditos = 5 AND cursando = 1 AND idGrupoCursando = @g5)
        THROW 54607, 'TEST FAILED: PE-04 E2 debe ver solo el plan de su programa.', 1;
    TRUNCATE TABLE #p;
    INSERT INTO #p (idPrograma, nombrePrograma, idPlanEstudio, inpPlanEstudio, idSemestrePlanEstudio, numeroSemestre, idAsignaturaPlanEstudio, idAsignatura,
        codigoAsignatura, nombreAsignatura, creditos, codigoComponente, nombreComponente, codigoCaracter, nombreCaracter, cursando, idGrupoCursando, nombreGrupoCursando)
    EXEC dbo.usp_consultar_plan_estudio_estudiante @idUsuarioEjecutor = @uDoc, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #p) <> 0
        THROW 54608, 'TEST FAILED: PE-04 un docente no ve un plan de estudiante.', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_plan_estudio_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 54609, 'TEST FAILED: PE-04 ejecutor nulo (esperaba VAL_001).', 1;
    PRINT 'TEST_PASS:HU018_PLAN_PRIVACIDAD';

    -- PE-05: contrato de columnas que lee el backend por nombre (18 columnas, en este orden).
    IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_plan_estudio_estudiante'), 0)) <> 18
       OR (SELECT STRING_AGG(CAST(d.name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY d.column_ordinal)
           FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_plan_estudio_estudiante'), 0) d)
          <> N'idPrograma,nombrePrograma,idPlanEstudio,inpPlanEstudio,idSemestrePlanEstudio,numeroSemestre,idAsignaturaPlanEstudio,idAsignatura,codigoAsignatura,nombreAsignatura,creditos,codigoComponente,nombreComponente,codigoCaracter,nombreCaracter,cursando,idGrupoCursando,nombreGrupoCursando'
        THROW 54610, 'TEST FAILED: PE-05 el plan del estudiante debe tener las 18 columnas del contrato, en orden.', 1;
    PRINT 'TEST_PASS:HU018_PLAN_COLUMNAS';

    -- HP-01: horas programadas de E1. G1: 3 sesiones no canceladas de 2 h (2 dictadas y 1 por dictar), la cancelada no cuenta.
    --        G3: sin sesiones => 0 y 0. G2 no aparece (matricula no inscrita).
    INSERT INTO #h (idEstudianteGrupo, idGrupo, sesionesProgramadas, horasProgramadas)
    EXEC dbo.usp_consultar_horas_programadas_estudiante @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #h) <> 2 OR EXISTS (SELECT 1 FROM #h WHERE idGrupo = @g2)
        THROW 54611, 'TEST FAILED: HP-01 se esperaban 2 filas (G1 y G3), sin la matricula no inscrita.', 1;
    IF NOT EXISTS (SELECT 1 FROM #h WHERE idGrupo = @g1 AND sesionesProgramadas = 3 AND horasProgramadas = 6.0)
        THROW 54612, 'TEST FAILED: HP-01 G1 debe tener 3 sesiones y 6 horas programadas (la cancelada no cuenta).', 1;
    IF NOT EXISTS (SELECT 1 FROM #h WHERE idGrupo = @g3 AND sesionesProgramadas = 0 AND horasProgramadas = 0)
        THROW 54613, 'TEST FAILED: HP-01 un grupo sin sesiones debe devolver 0 y 0.', 1;
    IF EXISTS (SELECT 1 FROM #h h WHERE NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.id = h.idEstudianteGrupo AND eg.estudiante = @e1))
        THROW 54614, 'TEST FAILED: HP-01 solo deben salir matriculas del propio estudiante.', 1;
    -- Las horas dictadas del resumen son un subconjunto de las programadas.
    IF EXISTS (SELECT 1 FROM #h h INNER JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = h.idEstudianteGrupo
               WHERE r.horasDictadas > h.horasProgramadas)
        THROW 54615, 'TEST FAILED: HP-01 las horas dictadas no pueden superar las programadas.', 1;
    PRINT 'TEST_PASS:HU019_HORAS_PROGRAMADAS';

    -- HP-02: quien no es estudiante no ve nada; ejecutor nulo => VAL_001; 4 columnas.
    TRUNCATE TABLE #h;
    INSERT INTO #h (idEstudianteGrupo, idGrupo, sesionesProgramadas, horasProgramadas)
    EXEC dbo.usp_consultar_horas_programadas_estudiante @idUsuarioEjecutor = @uDoc, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #h) <> 0
        THROW 54616, 'TEST FAILED: HP-02 un docente no ve horas programadas de estudiante.', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_horas_programadas_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=VAL_001|%'
        THROW 54617, 'TEST FAILED: HP-02 ejecutor nulo (esperaba VAL_001).', 1;
    IF (SELECT STRING_AGG(CAST(d.name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY d.column_ordinal)
        FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_horas_programadas_estudiante'), 0) d)
       <> N'idEstudianteGrupo,idGrupo,sesionesProgramadas,horasProgramadas'
        THROW 54618, 'TEST FAILED: HP-02 las horas programadas deben tener las 4 columnas del contrato, en orden.', 1;
    PRINT 'TEST_PASS:HU019_HORAS_VALIDACIONES';

    IF @@TRANCOUNT <> 1 THROW 54698, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 54699, 'TEST FAILED: test_hu018_hu019_plan_horas_estudiante dejo transacciones abiertas.', 1;
PRINT '==================================================';
PRINT 'TEST END: test_hu018_hu019_plan_horas_estudiante (HU018, HU019)';
PRINT '==================================================';
GO
