USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Revision final P3 (2026-11-22), defectos de base de datos BD-1..BD-10 (fixture de asignatura compartida de B2NM; todo en una transaccion revertida).
--   P3_BD_01 (BD-1)  previsualizacion de horario de una asignatura compartida: basta con coordinar ALGUN programa; quien no coordina ninguno: SEC_002
--   P3_BD_02 (BD-2)  eliminar un periodo sin grupos con recesos (activos y retirados) lo borra todo; con grupos: PER_004 y los recesos se conservan
--   P3_BD_03 (BD-3)  periodos con fechas solapadas: crear y actualizar rechazan con PER_012; contiguos y renombrar un historico solapado se permiten
--   P3_BD_04 (BD-4)  matricula manual solo con programa comun (EST_010 / EST_011 / EST_006); estudiante nuevo queda en el programa elegido
--   P3_BD_05 (BD-5)  numeroSemana de una sesion manual = semana del periodo (no su numero de orden)
--   P3_BD_06 (BD-6)  una solicitud de sesion rechazada no entra al cronograma, a los conteos ni al selector de sesiones del grupo
--   P3_BD_07 (BD-7)  KPIs y comparativa del decano exponen horasPeriodo (base del % de ausentismo)
--   P3_BD_08 (BD-8)  consolidado: las horas futuras van en porcentajePorDictar y no en porcentajeSinRegistro
--   P3_BD_09 (BD-9)  el listado de grupos del coordinador de otro programa trae el nombre del titular
--   P3_BD_11         el consolidado del coordinador solo trae filas de los programas que coordina (grupo compartido sin duplicar)
--   P3_BD_10 (BD-10) editar un grupo responde GEN_005 (actualizado), no GEN_004; mensajes nuevos sembrados
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_p3_revision_final_bd';
DROP TABLE IF EXISTS #apr; DROP TABLE IF EXISTS #can; DROP TABLE IF EXISTS #co; DROP TABLE IF EXISTS #cp; DROP TABLE IF EXISTS #g; DROP TABLE IF EXISTS #kd; DROP TABLE IF EXISTS #pv; DROP TABLE IF EXISTS #r; DROP TABLE IF EXISTS #res; DROP TABLE IF EXISTS #rp; DROP TABLE IF EXISTS #sg; DROP TABLE IF EXISTS #sol; 
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @tz NVARCHAR(128) = CONVERT(NVARCHAR(128), dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
    DECLARE @msg NVARCHAR(4000), @n INT;
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
    CREATE TABLE #rp (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL, idPeriodo UNIQUEIDENTIFIER NULL);
    CREATE TABLE #pv (tipoFila VARCHAR(12), orden INT, id1 UNIQUEIDENTIFIER, id2 UNIQUEIDENTIFIER, id3 UNIQUEIDENTIFIER,
        texto1 NVARCHAR(200), texto2 NVARCHAR(200), texto3 NVARCHAR(4000), texto4 NVARCHAR(200), texto5 NVARCHAR(200),
        fecha1 DATE, fecha2 DATE, instante1 DATETIME2, instante2 DATETIME2,
        e1 INT, e2 INT, e3 INT, e4 INT, e5 INT, e6 INT, e7 INT, e8 INT, e9 INT, e10 INT, e11 INT, e12 INT, e13 INT, e14 INT, e15 INT, e16 INT, e17 INT, e18 INT,
        b1 BIT, b2 BIT, e19 INT, e20 INT);

    -- Periodo de prueba nuevo, posterior a todos los existentes (sin solape) y en el futuro; el grupo G pasa a el.
    DECLARE @iniP DATE = DATEADD(DAY, 1, (SELECT MAX(fechaFin) FROM dbo.PeriodoAcademico WHERE institucion = @inst));
    IF @iniP < DATEADD(DAY, 30, CAST(SYSUTCDATETIME() AS DATE)) SET @iniP = DATEADD(DAY, 30, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @finP DATE = DATEADD(DAY, 111, @iniP);
    DECLARE @per UNIQUEIDENTIFIER = NEWID();
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @per, @nombre = N'P3 BD periodo', @fechaInicio = @iniP, @fechaFin = @finP, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 1)
        THROW 55001, 'TEST FAILED: P3_BD fixture: no se pudo crear el periodo de prueba (sin solape).', 1;
    UPDATE dbo.Grupo SET periodoAcademico = @per WHERE id = @grupoG;

    -- ------------------------------------------------------------------ P3_BD_01 (BD-1)
    DECLARE @h NVARCHAR(MAX) = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]';
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asigOPT, @idPeriodoAcademico = @per, @idDocente = @docT,
        @horariosJSON = @h, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'RESUMEN' AND id2 = @asigOPT)
        THROW 55011, 'TEST FAILED: P3_BD_01 el coordinador de UN programa de la asignatura compartida debe poder previsualizar (antes ASI_014 / 500).', 1;
    TRUNCATE TABLE #pv;
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asigOPT, @idPeriodoAcademico = @per, @idDocente = @docT,
        @horariosJSON = @h, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'RESUMEN')
        THROW 55012, 'TEST FAILED: P3_BD_01 el coordinador del otro programa de la asignatura compartida tambien debe poder previsualizar.', 1;
    PRINT 'TEST_PASS:P3_BD_01_PREVISUALIZAR_ASIGNATURA_COMPARTIDA';

    -- ------------------------------------------------------------------ P3_BD_02 (BD-2)
    DECLARE @iniQ DATE = DATEADD(DAY, 1, @finP), @perQ UNIQUEIDENTIFIER = NEWID();
    DECLARE @finQ DATE = DATEADD(DAY, 111, @iniQ);
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @perQ, @nombre = N'P3 BD periodo con recesos', @fechaInicio = @iniQ, @fechaFin = @finQ, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE idPeriodo = @perQ AND estadoResultado = 1)
        THROW 55021, 'TEST FAILED: P3_BD_02 fixture: no se pudo crear el periodo Q contiguo.', 1;
    INSERT INTO dbo.PeriodoRecesoAcademico (id, periodoAcademico, fecha, motivo, estaActivo, usuarioCreador, idCorrelacion)
    VALUES (NEWID(), @perQ, DATEADD(DAY, 10, @iniQ), N'Receso activo', 1, @uAdm, @c), (NEWID(), @perQ, DATEADD(DAY, 11, @iniQ), N'Receso retirado', 0, @uAdm, @c);
    -- con grupos: PER_004 y los recesos se conservan
    DECLARE @grupoQ UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grupoQ, @asigOPT, @perQ, @codGrupo + 1, N'P3-GQ', 30, 0, 0, 0, @docT);
    INSERT #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @perQ, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER[_]004%')
       OR (SELECT COUNT(*) FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico = @perQ) <> 2
        THROW 55022, 'TEST FAILED: P3_BD_02 un periodo con grupos debe responder PER_004 sin tocar sus recesos.', 1;
    DELETE FROM dbo.Grupo WHERE id = @grupoQ;
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_eliminar_periodo_academico @idPeriodo = @perQ, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perQ)
       OR EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico = @perQ)
        THROW 55023, 'TEST FAILED: P3_BD_02 un periodo sin grupos debe eliminarse junto con sus recesos (activos y retirados), sin error 500.', 1;
    PRINT 'TEST_PASS:P3_BD_02_ELIMINAR_PERIODO_CON_RECESOS';

    -- ------------------------------------------------------------------ P3_BD_03 (BD-3)
    DECLARE @perS UNIQUEIDENTIFIER = NEWID(), @perS2 UNIQUEIDENTIFIER = NEWID();
    -- solape total, parcial por el inicio y por el fin con el periodo de prueba
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD solape 1', @fechaInicio = @iniP, @fechaFin = @finP, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER[_]012%' AND mensajeUsuarioResultado LIKE N'%P3 BD periodo%')
       OR EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perS)
        THROW 55031, 'TEST FAILED: P3_BD_03 fechas identicas a otro periodo deben responder PER_012 (con el nombre del periodo en conflicto) sin crear nada.', 1;
    DELETE #rp;
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD solape 2', @fechaInicio = @finP, @fechaFin = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER[_]012%')
        THROW 55032, 'TEST FAILED: P3_BD_03 compartir un solo dia (limite inclusivo) debe responder PER_012.', 1;
    DELETE #rp;
    DECLARE @iniMenos20 DATE = DATEADD(DAY, -20, @iniP), @iniContiguo DATE = DATEADD(DAY, 1, @finP);
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD solape 3', @fechaInicio = @iniMenos20, @fechaFin = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER[_]012%')
        THROW 55033, 'TEST FAILED: P3_BD_03 un periodo que termina dentro de otro debe responder PER_012.', 1;
    -- contiguo (el dia siguiente) se permite
    DELETE #rp;
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD contiguo', @fechaInicio = @iniContiguo, @fechaFin = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perS)
        THROW 55034, 'TEST FAILED: P3_BD_03 un periodo contiguo (sin dias en comun) debe crearse.', 1;
    -- actualizar: mover el contiguo para que invada el periodo de prueba -> PER_012; moverlo mas adelante -> ok; renombrar un historico solapado -> ok
    DECLARE @iniS DATETIME2 = DATEADD(DAY, -5, @finP), @finSMal DATETIME2 = DATEADD(DAY, 111 - 5, @finP);
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_actualizar_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD contiguo', @fechaInicio = @iniS, @fechaFin = @finSMal, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER[_]012%')
       OR NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perS AND fechaInicio = DATEADD(DAY, 1, @finP))
        THROW 55035, 'TEST FAILED: P3_BD_03 actualizar un periodo hacia fechas que invaden otro debe responder PER_012 sin cambiar fechas.', 1;
    TRUNCATE TABLE #r;
    DECLARE @iniS2 DATETIME2 = DATEADD(DAY, 7, DATEADD(DAY, 1, @finP)), @finS2 DATETIME2 = DATEADD(DAY, 111 + 7, DATEADD(DAY, 1, @finP));
    INSERT #r EXEC dbo.usp_actualizar_periodo_academico @idPeriodo = @perS, @nombre = N'P3 BD contiguo', @fechaInicio = @iniS2, @fechaFin = @finS2, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 55036, 'TEST FAILED: P3_BD_03 actualizar un periodo sin solape (excluyendose a si mismo) debe aceptarse.', 1;
    -- un historico que ya se solapaba y solo cambia de nombre se conserva
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perS2, @inst, N'P3 BD historico solapado', 99992, DATEADD(DAY, 3, @iniP), DATEADD(DAY, 60, @iniP), YEAR(@iniP));
    DECLARE @iniH DATETIME2 = DATEADD(DAY, 3, @iniP), @finH DATETIME2 = DATEADD(DAY, 60, @iniP);
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_actualizar_periodo_academico @idPeriodo = @perS2, @nombre = N'P3 BD historico renombrado', @fechaInicio = @iniH, @fechaFin = @finH, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @perS2 AND nombre = N'P3 BD historico renombrado')
        THROW 55037, 'TEST FAILED: P3_BD_03 renombrar un periodo historico que ya se solapaba (sin cambiar fechas) debe aceptarse.', 1;
    PRINT 'TEST_PASS:P3_BD_03_PERIODOS_SIN_SOLAPE';

    -- ------------------------------------------------------------------ P3_BD_04 (BD-4)
    DECLARE @progC UNIQUEIDENTIFIER = NEWID(), @dominio NVARCHAR(255) = CONVERT(NVARCHAR(255), dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE'));
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@progC, @fac, @tipoProg, N'P3-Programa C', @coordB, 1);
    DECLARE @uEC UNIQUEIDENTIFIER = NEWID(), @eC UNIQUEIDENTIFIER = NEWID(), @uEA2 UNIQUEIDENTIFIER = NEWID(), @eA2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uEC,  @tipoCC, 1950000091, N'P3', N'', N'EstC',  N'', N'p3.estc@fixture.invalid',  1, 1),
           (@uEA2, @tipoCC, 1950000092, N'P3', N'', N'EstA2', N'', N'p3.esta2@fixture.invalid', 1, 1);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@eC, @uEC), (@eA2, @uEA2);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @eC, @progC), (NEWID(), @eA2, @progA);
    -- el grupo G necesita un periodo vigente para validar el grupo
    DECLARE @periodoEnCurso UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.uv_periodo_academico WHERE estado = 'ACTIVO' ORDER BY fechaInicio DESC, id);
    IF @periodoEnCurso IS NOT NULL UPDATE dbo.Grupo SET periodoAcademico = @periodoEnCurso WHERE id = @grupoG;
    -- EC (solo programa C, ajeno al grupo): EST_010 y sin escrituras
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupoG, @numeroIdentificacion = 1950000091, @primerNombre = N'P3', @segundoNombre = N'', @primerApellido = N'EstC',
        @segundoApellido = N'', @correo = N'p3.estc@fixture.invalid', @password = N'HashBackend_P3_1234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @uT,
        @idTipoIdIdentificacion = @tipoCC, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=EST[_]010%')
       OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @eC)
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @eC AND programa IN (@progA, @progB))
        THROW 55041, 'TEST FAILED: P3_BD_04 un estudiante sin programa comun con el grupo debe responder EST_010 sin matricula ni vinculo nuevo.', 1;
    -- EA2 (programa A) pero con programa elegido B (no es suyo): EST_011
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupoG, @numeroIdentificacion = 1950000092, @primerNombre = N'P3', @segundoNombre = N'', @primerApellido = N'EstA2',
        @segundoApellido = N'', @correo = N'p3.esta2@fixture.invalid', @password = N'HashBackend_P3_1234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @uT,
        @idTipoIdIdentificacion = @tipoCC, @idPrograma = @progB;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=EST[_]011%')
       OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @eA2)
        THROW 55042, 'TEST FAILED: P3_BD_04 un programa elegido que no es del estudiante debe responder EST_011.', 1;
    -- programa elegido ajeno al grupo: EST_006
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupoG, @numeroIdentificacion = 1950000092, @primerNombre = N'P3', @segundoNombre = N'', @primerApellido = N'EstA2',
        @segundoApellido = N'', @correo = N'p3.esta2@fixture.invalid', @password = N'HashBackend_P3_1234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @uT,
        @idTipoIdIdentificacion = @tipoCC, @idPrograma = @progC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=EST[_]006%')
        THROW 55043, 'TEST FAILED: P3_BD_04 un programa elegido ajeno al grupo debe responder EST_006.', 1;
    -- EA2 con su programa comun (A): se matricula, sin crear vinculos nuevos
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupoG, @numeroIdentificacion = 1950000092, @primerNombre = N'P3', @segundoNombre = N'', @primerApellido = N'EstA2',
        @segundoApellido = N'', @correo = N'p3.esta2@fixture.invalid', @password = N'HashBackend_P3_1234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @uT,
        @idTipoIdIdentificacion = @tipoCC, @idPrograma = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estudiante = @eA2)
       OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma WHERE estudiante = @eA2) <> 1
        THROW 55044, 'TEST FAILED: P3_BD_04 un estudiante con programa comun debe matricularse sin vinculos nuevos.', 1;
    -- estudiante NUEVO creado en el acto: queda vinculado al programa elegido del grupo (B)
    TRUNCATE TABLE #r;
    DECLARE @correoNuevo NVARCHAR(100) = CONCAT(N'p3.nuevo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio);
    DECLARE @docNuevo INT = 1100000000 + ABS(CHECKSUM(NEWID()) % 400000000);
    INSERT #r EXEC dbo.usp_registrar_estudiante_en_grupo @idGrupo = @grupoG, @numeroIdentificacion = @docNuevo, @primerNombre = N'P3', @segundoNombre = N'', @primerApellido = N'Nuevo',
        @segundoApellido = N'', @correo = @correoNuevo, @password = N'HashBackend_P3_1234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @uT,
        @idTipoIdIdentificacion = @tipoCC, @idPrograma = @progB;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep INNER JOIN dbo.Estudiante e ON e.id = ep.estudiante INNER JOIN dbo.Usuario u ON u.id = e.usuario
                      WHERE u.correo = LOWER(@correoNuevo) AND ep.programa = @progB)
        THROW 55045, 'TEST FAILED: P3_BD_04 el estudiante nuevo registrado por el docente debe quedar en el programa elegido del grupo.', 1;
    PRINT 'TEST_PASS:P3_BD_04_MATRICULA_MANUAL_PROGRAMA_COMUN';

    -- Sesiones manuales del docente para BD-5/6/7/8. El grupo debe estar en un periodo VIGENTE para crear sesiones: se inserta (como fixture, sin
    -- pasar por la regla de solape) un periodo de 112 dias que empieza 13 dias antes de hoy; hoy+4 cae en el dia 17 (semana 3) y hoy+87 en el dia 100 (semana 15).
    DECLARE @perAct UNIQUEIDENTIFIER = NEWID(), @iniAct DATE = DATEADD(DAY, -13, CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATE));
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perAct, @inst, N'P3 BD periodo vigente', 99993, @iniAct, DATEADD(DAY, 111, @iniAct), YEAR(@iniAct));
    UPDATE dbo.Grupo SET periodoAcademico = @perAct, programaResponsable = @progA WHERE id = @grupoG;   -- responsable = A (coordinador CA)
    DECLARE @dia DATE = DATEADD(DAY, 17, @iniAct);
    DECLARE @i1 DATETIME2 = CAST(DATEADD(HOUR, 5, CAST(@dia AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @i2 DATETIME2 = DATEADD(DAY, 1, @i1), @i3 DATETIME2 = DATEADD(DAY, 2, @i1);
    DECLARE @e1 DATETIME2 = DATEADD(HOUR, 2, @i1), @e2 DATETIME2 = DATEADD(HOUR, 2, @i2), @e3 DATETIME2 = DATEADD(HOUR, 2, @i3);
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'P3 aprobada', @fechaHoraInicio = @i1, @fechaHoraFin = @e1, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    INSERT #r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'P3 pendiente', @fechaHoraInicio = @i2, @fechaHoraFin = @e2, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    INSERT #r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'P3 rechazada', @fechaHoraInicio = @i3, @fechaHoraFin = @e3, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 3
    BEGIN
        SET @msg = (SELECT TOP 1 CONCAT(mensajeTecnicoResultado, N' / ', mensajeUsuarioResultado) FROM #r WHERE estadoResultado = 0);
        SET @msg = CONCAT(N'TEST FAILED: P3_BD fixture: las 3 sesiones manuales debieron crearse. ', @msg);
        THROW 55050, @msg, 1;
    END
    DECLARE @sApr UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'P3 aprobada');
    DECLARE @sPen UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'P3 pendiente');
    DECLARE @sRec UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'P3 rechazada');

    -- P3_BD_05: semana del periodo (dia 17 => semana 3, dias 18 y 19 => semana 3); el numero de orden es 1, 2 y 3
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id IN (@sApr, @sPen, @sRec) AND numeroSemana <> 3)
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sApr AND numero = 1)
        THROW 55051, 'TEST FAILED: P3_BD_05 numeroSemana de una sesion manual debe ser la semana del periodo (3), no su numero de orden.', 1;
    -- una sesion lejana (dia 100 => semana 15) con numero de orden 4
    DECLARE @iL DATETIME2 = CAST(DATEADD(HOUR, 5, CAST(DATEADD(DAY, 100, @iniAct) AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @eL DATETIME2 = DATEADD(HOUR, 2, @iL);
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'P3 lejana', @fechaHoraInicio = @iL, @fechaHoraFin = @eL, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'P3 lejana' AND numero = 4 AND numeroSemana = 15)
        THROW 55052, 'TEST FAILED: P3_BD_05 una sesion manual del dia 100 del periodo debe quedar en la semana 15.', 1;
    PRINT 'TEST_PASS:P3_BD_05_NUMERO_SEMANA_SESION_MANUAL';

    -- P3_BD_06: aprobar A, rechazar R; P queda pendiente
    DECLARE @motivo NVARCHAR(50) = (SELECT TOP 1 codigo FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    CREATE TABLE #apr (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaHoraInicio DATETIME2 NULL, totalEstudiantesActivos INT NULL);
    CREATE TABLE #can (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL, totalEstudiantesActivos INT NULL);
    INSERT #apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sApr, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    INSERT #can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sRec, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #apr WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 1)
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: P3_BD_06 fixture: aprobar y rechazar debieron ejecutarse. ',
                          (SELECT TOP 1 mensajeTecnicoResultado FROM #apr WHERE estadoResultado = 0), N' | ', (SELECT TOP 1 mensajeTecnicoResultado FROM #can WHERE estadoResultado = 0));
        THROW 55060, @msg, 1;
    END
    CREATE TABLE #res (idSesion UNIQUEIDENTIFIER, numero INT, nombre NVARCHAR(200), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, procedenciaTemporal NVARCHAR(24),
        estadoSesion NVARCHAR(20), estadoSolicitud NVARCHAR(50), pendienteAprobacion BIT, totalEstudiantes INT, presentes INT, parciales INT, justificadas INT, ausentes INT, sinRegistro INT,
        sesionesProgramadas INT, sesionesEjecutadas INT, sesionesCanceladas INT, sesionesEnCurso INT, idSesionEnCurso UNIQUEIDENTIFIER, idSesionProxima UNIQUEIDENTIFIER,
        estudiantesActivos INT, estudiantesEnRiesgo INT, promedioAsistencia DECIMAL(5,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2));
    INSERT #res EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF EXISTS (SELECT 1 FROM #res WHERE idSesion = @sRec)
       OR NOT EXISTS (SELECT 1 FROM #res WHERE idSesion = @sApr) OR NOT EXISTS (SELECT 1 FROM #res WHERE idSesion = @sPen)
       OR EXISTS (SELECT 1 FROM #res WHERE sesionesProgramadas <> 3 OR sesionesCanceladas <> 0)
        THROW 55061, 'TEST FAILED: P3_BD_06 el cronograma del docente no debe listar ni contar la solicitud rechazada (3 programadas: aprobada, pendiente y lejana; 0 canceladas).', 1;
    CREATE TABLE #sg (id UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(200), nombre NVARCHAR(200), numero INT, codigo NVARCHAR(50),
        numeroSemana INT, fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, totalRegistros INT, estaCancelada BIT, codigoTipoCancelacion NVARCHAR(50), motivoCancelacion NVARCHAR(500),
        nombreDiaFestivo NVARCHAR(200), fechaCancelacionUtc DATETIME2 NULL);
    INSERT #sg EXEC dbo.usp_consultar_sesiones_grupo_paginado @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = @grupoG, @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #sg WHERE id = @sRec) OR (SELECT COUNT(*) FROM #sg) <> 3
        THROW 55062, 'TEST FAILED: P3_BD_06 el selector de sesiones del grupo no debe incluir la solicitud rechazada.', 1;
    -- sigue visible en las solicitudes de sesion del docente
    CREATE TABLE #sol (idSesion UNIQUEIDENTIFIER, nombreSesion NVARCHAR(200), codigoSesion NVARCHAR(50), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2,
        estadoSolicitud NVARCHAR(30), nombreEstadoSolicitud NVARCHAR(100), fechaSolicitudUtc DATETIME2, fechaResolucionUtc DATETIME2 NULL, observacion NVARCHAR(500) NULL,
        usuarioSolicitante UNIQUEIDENTIFIER, pendienteAprobacion BIT, estaCancelada BIT, totalRegistros INT,
        nombreProgramaResponsable NVARCHAR(200) NULL, nombreCoordinadorResolutor NVARCHAR(400) NULL);
    INSERT #sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @soloPendientes = 0, @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #sol WHERE idSesion = @sRec)
        THROW 55063, 'TEST FAILED: P3_BD_06 la solicitud rechazada debe seguir en Solicitudes de sesion.', 1;
    PRINT 'TEST_PASS:P3_BD_06_SOLICITUD_RECHAZADA_FUERA_DEL_CRONOGRAMA';

    -- P3_BD_07: horasPeriodo AL FINAL de los KPIs y la comparativa del decano (la sesion aprobada de 2 h cuenta para los matriculados con programa)
    CREATE TABLE #kd (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
        totalProgramas INT, totalEstudiantes INT, estudiantesRegulares INT, estudiantesRiesgo INT, estudiantesPerdida INT, tasaRetencion DECIMAL(5,2),
        sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), porcentajeAsistencia DECIMAL(5,2),
        gruposActivos INT, cupoTotal INT, matriculadosActivos INT, tasaAforo DECIMAL(7,2), umbralAdvertencia DECIMAL(5,2), umbralPerdida DECIMAL(5,2),
        tomasDictadas INT, horasDictadas DECIMAL(12,6), horasFalta DECIMAL(12,6), totalCoordinadores INT, totalDocentes INT, horasPeriodo DECIMAL(12,6));
    INSERT #kd EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = @perAct;
    IF NOT EXISTS (SELECT 1 FROM #kd WHERE horasPeriodo > 0 AND horasDictadas = 0 AND horasFalta = 0 AND porcentajeAusentismo = 0.00)
        THROW 55071, 'TEST FAILED: P3_BD_07 los KPIs del decano deben exponer horasPeriodo > 0 (base del %) con horasDictadas = 0 y ausentismo 0 %.', 1;
    DECLARE @ultimaKd SYSNAME = (SELECT TOP 1 name FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_kpis_decano'), NULL) ORDER BY column_ordinal DESC);
    DECLARE @ultimaCp SYSNAME = (SELECT TOP 1 name FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'), NULL) ORDER BY column_ordinal DESC);
    IF @ultimaKd <> N'horasPeriodo' OR @ultimaCp <> N'horasPeriodo'
        THROW 55072, 'TEST FAILED: P3_BD_07 horasPeriodo debe ser la ultima columna (cambio aditivo) de kpis_decano y comparativa_programas_facultad.', 1;
    CREATE TABLE #cp (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), estaActivoPrograma BIT, totalEstudiantes INT, estudiantesRiesgo INT, estudiantesPerdida INT,
        tasaRetencion DECIMAL(5,2), sesionesEjecutadas INT, faltasSinJustaCausa INT, porcentajeAusentismo DECIMAL(5,2), horasDictadas DECIMAL(12,2), horasFalta DECIMAL(12,2), horasPeriodo DECIMAL(12,2));
    INSERT #cp EXEC dbo.usp_consultar_comparativa_programas_facultad @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPeriodoAcademico = @perAct;
    IF NOT EXISTS (SELECT 1 FROM #cp WHERE idPrograma = @progA AND horasPeriodo > 0 AND porcentajeAusentismo = 0.00)
       OR EXISTS (SELECT 1 FROM #cp WHERE horasPeriodo = 0 AND porcentajeAusentismo IS NOT NULL)
        THROW 55073, 'TEST FAILED: P3_BD_07 la comparativa debe exponer horasPeriodo y dejar el % nulo solo si no hay horas del periodo.', 1;
    PRINT 'TEST_PASS:P3_BD_07_HORAS_PERIODO_DECANO';

    -- P3_BD_08: consolidado del programa A: sin horas dictadas, todo lo restante es "por dictar" y nada es "sin registro"
    CREATE TABLE #co (idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        nombrePeriodoAcademico NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100),
        idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(250),
        estudiantesActivos INT, sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT,
        porcentajeAsistencia DECIMAL(5,2), porcentajeInasistencia DECIMAL(5,2), estudiantesRiesgo INT, estudiantesPerdida INT, totalRegistros INT,
        horasDictadas DECIMAL(12,2), porcentajeExcusa DECIMAL(5,2), porcentajeSinRegistro DECIMAL(5,2), codigoPermanencia NVARCHAR(10), porcentajePorDictar DECIMAL(5,2));
    INSERT #co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @idPeriodoAcademico = @perAct, @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #co WHERE idGrupo = @grupoG AND horasDictadas = 0 AND porcentajeSinRegistro = 0.00 AND porcentajePorDictar = 100.00
                   AND porcentajeAsistencia = 0.00 AND porcentajeInasistencia = 0.00 AND porcentajeExcusa = 0.00)
       OR EXISTS (SELECT 1 FROM #co WHERE porcentajeAsistencia + porcentajeInasistencia + porcentajeExcusa + porcentajeSinRegistro + porcentajePorDictar <> 100.00
                                       AND porcentajeAsistencia + porcentajeInasistencia + porcentajeExcusa + porcentajeSinRegistro + porcentajePorDictar <> 0)
        THROW 55081, 'TEST FAILED: P3_BD_08 sin horas dictadas el consolidado debe dar 0 % sin registro y 100 % por dictar (las cinco columnas suman 100).', 1;
    PRINT 'TEST_PASS:P3_BD_08_CONSOLIDADO_SIN_REGISTRO_SOLO_DICTADAS';

    -- P3_BD_11: el consolidado del coordinador trae SOLO las filas de los programas que el coordina (un grupo compartido ya no se duplica con el programa ajeno)
    TRUNCATE TABLE #co;
    INSERT #co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @idPeriodoAcademico = @perAct;
    IF (SELECT COUNT(*) FROM #co WHERE idGrupo = @grupoG) <> 1 OR NOT EXISTS (SELECT 1 FROM #co WHERE idGrupo = @grupoG AND idPrograma = @progA)
        THROW 55111, 'TEST FAILED: P3_BD_11 el coordinador del programa A debe ver una sola fila del grupo compartido (la de su programa), no la del programa B.', 1;
    TRUNCATE TABLE #co;
    INSERT #co EXEC dbo.usp_consultar_consolidado_asistencia_grupos_paginado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @idPeriodoAcademico = @perAct;
    IF (SELECT COUNT(*) FROM #co WHERE idGrupo = @grupoG) <> 1 OR NOT EXISTS (SELECT 1 FROM #co WHERE idGrupo = @grupoG AND idPrograma = @progB)
        THROW 55112, 'TEST FAILED: P3_BD_11 el coordinador del programa B debe ver una sola fila del grupo compartido (la de su programa).', 1;
    PRINT 'TEST_PASS:P3_BD_11_CONSOLIDADO_SOLO_PROGRAMAS_DEL_AMBITO';

    -- P3_BD_09: el coordinador del programa B (no responsable) ve al titular aunque no este vinculado a su programa
    DELETE FROM dbo.DocentePrograma WHERE docente = @docT AND programa = @progB;
    CREATE TABLE #g (id UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
        idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT, cuposDisponibles INT, grupoEstaHablitado BIT,
        fechaInicioPeriodoAcademico DATETIME2, fechaFinPeriodoAcademico DATETIME2, totalRegistros INT, idProgramaResponsable UNIQUEIDENTIFIER,
        nombreProgramaResponsable NVARCHAR(50), esResponsable BIT, nombreDocente NVARCHAR(300));
    INSERT #g EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c, @idPeriodoAcademico = @perAct, @tamanoPagina = NULL;
    DECLARE @nombreDocT NVARCHAR(300) = (SELECT nombreCompleto FROM dbo.uv_docente_identidad WHERE id = @docT);
    IF @nombreDocT IS NULL OR NOT EXISTS (SELECT 1 FROM #g WHERE id = @grupoG AND esResponsable = 0 AND nombreDocente = @nombreDocT)
        THROW 55091, 'TEST FAILED: P3_BD_09 el coordinador de otro programa debe ver el nombre del titular en el listado de grupos.', 1;
    PRINT 'TEST_PASS:P3_BD_09_NOMBRE_DOCENTE_GRUPO_COMPARTIDO';

    -- P3_BD_10: editar un grupo responde GEN_005; mensajes nuevos sembrados
    DECLARE @codG INT = (SELECT codigo FROM dbo.Grupo WHERE id = @grupoG);
    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_actualizar_grupo @idGrupo = @grupoG, @codigo = @codG, @nombre = N'P3-G editado', @idDocente = @docT, @cupoMaximo = 30, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    DECLARE @gen005 NVARCHAR(4000), @gen004 NVARCHAR(4000), @tec NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Grupo', @mensajeUsuarioResultado = @gen005 OUTPUT, @mensajeTecnicoResultado = @tec OUTPUT;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Grupo', @mensajeUsuarioResultado = @gen004 OUTPUT, @mensajeTecnicoResultado = @tec OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @gen005) OR @gen005 = @gen004 OR @gen005 NOT LIKE N'Grupo actualizado%'
        THROW 55101, 'TEST FAILED: P3_BD_10 editar un grupo debe responder el mensaje de actualizacion (GEN_005) y no el de registro.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE estaActivo = 1 AND tipoMensaje = 'BUSINESS_ERROR' AND codigo IN ('PER_012', 'EST_010', 'EST_011')) <> 3
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE estaActivo = 1 AND codigo IN ('PER_012', 'EST_010', 'EST_011')) <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PER_012' AND contenido = N'Las fechas del período se cruzan con el período {}; los períodos de la institución no pueden solaparse.')
        THROW 55102, 'TEST FAILED: P3_BD_10 faltan los mensajes PER_012, EST_010 o EST_011 (usuario y tecnico) o su texto no es el institucional.', 1;
    PRINT 'TEST_PASS:P3_BD_10_MENSAJES_Y_ACTUALIZACION_GRUPO';

    -- P3_BD_01B: va al final porque el THROW 51000 de la lectura (con XACT_ABORT ON) deja la transaccion condenada.
    -- un coordinador que no coordina ningun programa de la asignatura: SEC_002 (ya no ASI_014)
    DECLARE @uCX UNIQUEIDENTIFIER = NEWID(), @coordCX UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uCX, @tipoCC, 1950000090, N'P3', N'', N'CoordX', N'', N'p3.coordx@fixture.invalid', 1, 1);
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordCX, @uCX, 1, @fac);
    SET @msg = NULL;
    BEGIN TRY
        TRUNCATE TABLE #pv;
        INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asigOPT, @idPeriodoAcademico = @perAct, @idDocente = @docT,
            @horariosJSON = @h, @idCorrelacion = @c, @idUsuarioEjecutor = @uCX;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
    END CATCH
    IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
    IF @msg IS NULL OR @msg NOT LIKE N'DBCODE=SEC[_]002%'
        THROW 55013, 'TEST FAILED: P3_BD_01B un coordinador sin programa de la asignatura debe recibir SEC_002.', 1;
    PRINT 'TEST_PASS:P3_BD_01B_PREVISUALIZAR_SIN_PROGRAMA_SEC_002';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 55199, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:P3_BD_TRANCOUNT_ZERO';
GO
