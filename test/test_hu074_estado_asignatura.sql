USE [gestionasistenciadb];
GO
-- HU074 (migracion 57): activar o inactivar asignaturas. Fixtures propias dentro de UNA transaccion con ROLLBACK final (no deja datos).
--   HU074_01_INACTIVAR_SIN_GRUPOS        sin grupos: queda inactiva con ASI_012
--   HU074_02_REACTIVAR                   reactivar siempre se permite: ASI_011
--   HU074_03_GRUPO_PERIODO_VIGENTE       grupo en el periodo vigente: ASI_009 y no cambia
--   HU074_04_GRUPO_PERIODO_FUTURO        grupo en un periodo futuro: ASI_009 y no cambia
--   HU074_05_GRUPO_SOLO_PERIODO_PASADO   grupos solo en periodos pasados: se inactiva (ASI_012)
--   HU074_06_COMPARTIDA_PROGRAMA_AJENO   compartida con un programa que no coordina: ASI_006 y no cambia
--   HU074_07_CREAR_GRUPO_INACTIVA        usp_crear_grupo con una asignatura inactiva: ASI_010 y no inserta
--   HU074_08_ASOCIAR_PLAN_INACTIVA       usp_asociar_asignatura_plan con una asignatura inactiva: ASI_010 y no crea vinculo
--   HU074_09_OFERTA_EXCLUYE_INACTIVA     usp_consultar_oferta_creacion_grupo_docente no ofrece la inactiva (si la activa)
--   HU074_10_ASOCIABLES_EXCLUYE_INACTIVA usp_consultar_asignaturas_asociables_paginado no ofrece la inactiva (si la activa)
--   HU074_11_MALLA_MUESTRA_INACTIVA      usp_consultar_asignaturas_plan_paginado muestra la inactiva con estaActivaAsignatura = 0
--   HU074_12_DESEADA_INACTIVA_YA_INACTIVA @estaActivaDeseada = 0 sobre una inactiva: exito ASI_012 sin cambio
--   HU074_13_DESEADA_ACTIVA_YA_ACTIVA    @estaActivaDeseada = 1 sobre una activa (con grupos vigentes): exito ASI_011 sin cambio
--   HU074_14_DESEADA_ACTIVA_DESDE_INACTIVA @estaActivaDeseada = 1 sobre una inactiva: la activa (ASI_011)
--   HU074_15_COMPARTIDA_PROPIA_CON_GRUPO compartida entre programas del mismo coordinador, con grupo vigente: ASI_009 (no ASI_006)
--   HU074_16_BORDE_FIN_HOY               grupo en un periodo con fechaFin = hoy (fecha local institucional): vigente, ASI_009
--   HU074_17_BORDE_INICIO_MANANA         grupo en un periodo con fechaInicio = manana: futuro, ASI_009 (tambien con @estaActivaDeseada = 0)
--   HU074_18_CREAR_GRUPO_ACTIVA          usp_crear_grupo con una asignatura activa sigue creando el grupo (GEN_004) dentro de la
--                                        transaccion del llamador (regresion del bloqueo y la transaccion de la 57)
--   HU074_TRANCOUNT_ZERO                 no deja transacciones abiertas
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_hu074_estado_asignatura';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa ORDER BY id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @idFacultad);
DECLARE @idTipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY id);
DECLARE @idSemestre UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre ORDER BY numero);
DECLARE @numSemestre INT = (SELECT numero FROM dbo.Semestre WHERE id = @idSemestre);
DECLARE @idCaracter UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OBL');
DECLARE @idArea UNIQUEIDENTIFIER, @idComponente UNIQUEIDENTIFIER;
SELECT TOP 1 @idArea = area, @idComponente = componente FROM dbo.Asignatura ORDER BY id;
IF @tipoCC IS NULL OR @idFacultad IS NULL OR @idInstitucion IS NULL OR @idTipoProg IS NULL OR @idSemestre IS NULL OR @idCaracter IS NULL OR @idArea IS NULL
    THROW 57400, 'TEST FAILED: HU074 faltan fixtures base.', 1;

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000) COLLATE DATABASE_DEFAULT, mt NVARCHAR(4000) COLLATE DATABASE_DEFAULT, estado BIT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);
-- Bordes: misma fecha local institucional que uv_periodo_academico (TIEMPO/ZONA_HORARIA_SQLSERVER)
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uC UNIQUEIDENTIFIER = NEWID(), @uC2 UNIQUEIDENTIFIER = NEWID(), @uD UNIQUEIDENTIFIER = NEWID();
    DECLARE @cC UNIQUEIDENTIFIER = NEWID(), @cC2 UNIQUEIDENTIFIER = NEWID(), @dD UNIQUEIDENTIFIER = NEWID();
    DECLARE @p1 UNIQUEIDENTIFIER = NEWID(), @p2 UNIQUEIDENTIFIER = NEWID(), @p3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @pl1 UNIQUEIDENTIFIER = NEWID(), @pl2 UNIQUEIDENTIFIER = NEWID(), @pl3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @spe1 UNIQUEIDENTIFIER = NEWID(), @spe2 UNIQUEIDENTIFIER = NEWID(), @spe3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @aLibre UNIQUEIDENTIFIER = NEWID(), @aVig UNIQUEIDENTIFIER = NEWID(), @aFut UNIQUEIDENTIFIER = NEWID();
    DECLARE @aPas UNIQUEIDENTIFIER = NEWID(), @aComp UNIQUEIDENTIFIER = NEWID();
    DECLARE @aCompPropia UNIQUEIDENTIFIER = NEWID(), @aBordeFin UNIQUEIDENTIFIER = NEWID(), @aBordeIni UNIQUEIDENTIFIER = NEWID();
    DECLARE @perBordeFin UNIQUEIDENTIFIER = NEWID(), @perBordeIni UNIQUEIDENTIFIER = NEWID();
    DECLARE @grupoActiva UNIQUEIDENTIFIER = NEWID();
    DECLARE @perPas UNIQUEIDENTIFIER = NEWID(), @perVig UNIQUEIDENTIFIER = NEWID(), @perFut UNIQUEIDENTIFIER = NEWID();
    DECLARE @codPer INT = (SELECT ISNULL(MAX(codigo), 0) FROM dbo.PeriodoAcademico);
    DECLARE @codGrupo INT = (SELECT ISNULL(MAX(codigo), 0) + 7400 FROM dbo.Grupo);
    DECLARE @grupoNuevo UNIQUEIDENTIFIER = NEWID();
    DECLARE @codGrupoNuevo INT = @codGrupo + 9;
    DECLARE @codGrupoActiva INT = @codGrupo + 10;

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uC,  @tipoCC, 974070001, N'Coord', N'Uno', N'Hugo', N'Qa', N'qa.c1.hu074@test.local', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
           (@uC2, @tipoCC, 974070002, N'Coord', N'Dos', N'Hilda', N'Qa', N'qa.c2.hu074@test.local', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
           (@uD,  @tipoCC, 974070003, N'Docente', N'Uno', N'Hector', N'Qa', N'qa.doc.hu074@test.local', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@cC, @uC), (@cC2, @uC2);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dD, @uD);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@p1, @idFacultad, @idTipoProg, N'Programa QA HU074-1', @cC, 1),
           (@p2, @idFacultad, @idTipoProg, N'Programa QA HU074-2', @cC, 1),
           (@p3, @idFacultad, @idTipoProg, N'Programa QA HU074-3', @cC2, 1);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@pl1, @p1, 97401, 1), (@pl2, @p2, 97402, 1), (@pl3, @p3, 97403, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@spe1, @pl1, @idSemestre), (@spe2, @pl2, @idSemestre), (@spe3, @pl3, @idSemestre);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, estado, fechaVinculacionUtc) VALUES (NEWID(), @dD, @p1, 1, SYSUTCDATETIME());
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado) VALUES
        (@aLibre, N'QAHU074L', N'QA HU074 Libre', 3, @idArea, @idComponente, 1),
        (@aVig,   N'QAHU074V', N'QA HU074 Vigente', 3, @idArea, @idComponente, 1),
        (@aFut,   N'QAHU074F', N'QA HU074 Futuro', 3, @idArea, @idComponente, 1),
        (@aPas,   N'QAHU074P', N'QA HU074 Pasado', 3, @idArea, @idComponente, 1),
        (@aComp,  N'QAHU074C', N'QA HU074 Compartida', 3, @idArea, @idComponente, 1),
        (@aCompPropia, N'QAHU074K', N'QA HU074 Compartida propia', 3, @idArea, @idComponente, 1),
        (@aBordeFin,   N'QAHU074B', N'QA HU074 Borde fin', 3, @idArea, @idComponente, 1),
        (@aBordeIni,   N'QAHU074I', N'QA HU074 Borde inicio', 3, @idArea, @idComponente, 1);
    INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc)
    SELECT NEWID(), x.a, x.spe, @idCaracter, 1, '2020-01-01'
    FROM (VALUES (@aLibre, @spe1), (@aVig, @spe1), (@aFut, @spe1), (@aPas, @spe1), (@aComp, @spe1), (@aComp, @spe3),
                 (@aCompPropia, @spe1), (@aCompPropia, @spe2), (@aBordeFin, @spe1), (@aBordeIni, @spe1)) x (a, spe);
    -- Periodos con margen amplio respecto de hoy (la fecha local institucional difiere de la UTC en horas, no en meses)
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perPas, @idInstitucion, N'QA HU074 Pasado',  @codPer + 1, DATEADD(DAY, -300, @hoy), DATEADD(DAY, -200, @hoy), YEAR(DATEADD(DAY, -300, @hoy))),
           (@perVig, @idInstitucion, N'QA HU074 Vigente', @codPer + 2, DATEADD(DAY, -30, @hoy),  DATEADD(DAY, 30, @hoy),   YEAR(@hoy)),
           (@perFut, @idInstitucion, N'QA HU074 Futuro',  @codPer + 3, DATEADD(DAY, 200, @hoy),  DATEADD(DAY, 300, @hoy),  YEAR(DATEADD(DAY, 200, @hoy))),
           (@perBordeFin, @idInstitucion, N'QA HU074 Borde fin',    @codPer + 4, DATEADD(DAY, -60, @hoyLocal), @hoyLocal, YEAR(@hoyLocal)),
           (@perBordeIni, @idInstitucion, N'QA HU074 Borde inicio', @codPer + 5, DATEADD(DAY, 1, @hoyLocal), DATEADD(DAY, 90, @hoyLocal), YEAR(DATEADD(DAY, 1, @hoyLocal)));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (NEWID(), @aVig, @perVig, @codGrupo + 1, N'QA HU074 G1', 30, 0, 0, 0, @dD),
           (NEWID(), @aVig, @perPas, @codGrupo + 2, N'QA HU074 G2', 30, 0, 0, 0, @dD),
           (NEWID(), @aFut, @perFut, @codGrupo + 3, N'QA HU074 G3', 30, 0, 0, 0, @dD),
           (NEWID(), @aPas, @perPas, @codGrupo + 4, N'QA HU074 G4', 30, 0, 0, 0, @dD),
           (NEWID(), @aCompPropia, @perVig, @codGrupo + 5, N'QA HU074 G5', 30, 0, 0, 0, @dD),
           (NEWID(), @aBordeFin, @perBordeFin, @codGrupo + 6, N'QA HU074 G6', 30, 0, 0, 0, @dD),
           (NEWID(), @aBordeIni, @perBordeIni, @codGrupo + 7, N'QA HU074 G7', 30, 0, 0, 0, @dD);
    IF (SELECT estado FROM dbo.uv_periodo_academico WHERE id = @perBordeFin) <> 'ACTIVO'
       OR (SELECT estado FROM dbo.uv_periodo_academico WHERE id = @perBordeIni) <> 'PLANEACION'
        THROW 57420, 'TEST FAILED: HU074 los periodos de borde no quedaron ACTIVO (fin hoy) y PLANEACION (inicio manana).', 1;

    -- HU074_01: inactivar sin grupos -> ASI_012
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aLibre, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND idCorrelacion = @corr AND mt LIKE N'DBCODE=ASI[_]012|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_012'))
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aLibre AND estado = 0)
        THROW 57401, 'TEST FAILED: HU074_01 inactivar sin grupos debe dar ASI_012 y dejarla inactiva.', 1;
    PRINT 'TEST_PASS:HU074_01_INACTIVAR_SIN_GRUPOS';

    -- HU074_02: reactivar -> ASI_011
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aLibre, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=ASI[_]011|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_011'))
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aLibre AND estado = 1)
        THROW 57402, 'TEST FAILED: HU074_02 reactivar debe dar ASI_011 y dejarla activa.', 1;
    PRINT 'TEST_PASS:HU074_02_REACTIVAR';

    -- HU074_03: grupo en el periodo vigente (y otro en uno pasado) -> ASI_009
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aVig, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]009|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_009'))
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aVig AND estado = 1)
        THROW 57403, 'TEST FAILED: HU074_03 grupo en el periodo vigente debe dar ASI_009 sin cambiar el estado.', 1;
    PRINT 'TEST_PASS:HU074_03_GRUPO_PERIODO_VIGENTE';

    -- HU074_04: grupo en un periodo futuro -> ASI_009
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aFut, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]009|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aFut AND estado = 1)
        THROW 57404, 'TEST FAILED: HU074_04 grupo en un periodo futuro debe dar ASI_009 sin cambiar el estado.', 1;
    PRINT 'TEST_PASS:HU074_04_GRUPO_PERIODO_FUTURO';

    -- HU074_05: grupos solo en periodos pasados -> se inactiva
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aPas, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=ASI[_]012|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aPas AND estado = 0)
        THROW 57405, 'TEST FAILED: HU074_05 con grupos solo en periodos pasados debe inactivarse (ASI_012).', 1;
    PRINT 'TEST_PASS:HU074_05_GRUPO_SOLO_PERIODO_PASADO';

    -- HU074_06: compartida con un programa que no coordina -> ASI_006
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aComp, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]006|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aComp AND estado = 1)
        THROW 57406, 'TEST FAILED: HU074_06 asignatura compartida con un programa ajeno debe dar ASI_006.', 1;
    PRINT 'TEST_PASS:HU074_06_COMPARTIDA_PROGRAMA_AJENO';

    -- HU074_12: @estaActivaDeseada = 0 sobre una ya inactiva (@aPas quedo inactiva en HU074_05) -> exito ASI_012 sin cambio
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aPas, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC, @estaActivaDeseada = 0;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=ASI[_]012|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_012'))
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aPas AND estado = 0)
        THROW 57412, 'TEST FAILED: HU074_12 pedir inactiva sobre una inactiva debe dar ASI_012 sin cambiarla.', 1;
    PRINT 'TEST_PASS:HU074_12_DESEADA_INACTIVA_YA_INACTIVA';

    -- HU074_13: @estaActivaDeseada = 1 sobre una activa con grupos vigentes -> exito ASI_011 sin cambio (no evalua grupos)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aVig, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC, @estaActivaDeseada = 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=ASI[_]011|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_011'))
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aVig AND estado = 1)
        THROW 57413, 'TEST FAILED: HU074_13 pedir activa sobre una activa debe dar ASI_011 sin cambiarla.', 1;
    PRINT 'TEST_PASS:HU074_13_DESEADA_ACTIVA_YA_ACTIVA';

    -- HU074_14: @estaActivaDeseada = 1 sobre una inactiva -> la activa (ASI_011)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aPas, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC, @estaActivaDeseada = 1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=ASI[_]011|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aPas AND estado = 1)
        THROW 57414, 'TEST FAILED: HU074_14 pedir activa sobre una inactiva debe activarla (ASI_011).', 1;
    PRINT 'TEST_PASS:HU074_14_DESEADA_ACTIVA_DESDE_INACTIVA';

    -- HU074_15: compartida entre P1 y P2 (ambos del coordinador C) con grupo vigente -> ASI_009, no ASI_006
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aCompPropia, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]009|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aCompPropia AND estado = 1)
        THROW 57415, 'TEST FAILED: HU074_15 compartida entre programas propios con grupo vigente debe dar ASI_009.', 1;
    PRINT 'TEST_PASS:HU074_15_COMPARTIDA_PROPIA_CON_GRUPO';

    -- HU074_16: grupo en un periodo que termina hoy (fecha local institucional) -> vigente, ASI_009
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aBordeFin, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]009|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aBordeFin AND estado = 1)
        THROW 57416, 'TEST FAILED: HU074_16 grupo en un periodo con fechaFin = hoy debe dar ASI_009.', 1;
    PRINT 'TEST_PASS:HU074_16_BORDE_FIN_HOY';

    -- HU074_17: grupo en un periodo que empieza manana -> futuro, ASI_009 (tambien pidiendo @estaActivaDeseada = 0)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @aBordeIni, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC, @estaActivaDeseada = 0;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]009|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @aBordeIni AND estado = 1)
        THROW 57417, 'TEST FAILED: HU074_17 grupo en un periodo con fechaInicio = manana debe dar ASI_009.', 1;
    PRINT 'TEST_PASS:HU074_17_BORDE_INICIO_MANANA';

    -- HU074_18: crear grupo con una asignatura activa sigue funcionando dentro de la transaccion del llamador
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @grupoActiva, @idAsignatura = @aVig, @idPeriodoAcademico = @perFut, @codigo = @codGrupoActiva,
        @nombre = N'QA HU074 Activa', @idDocente = @dD, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 1 AND mt LIKE N'DBCODE=GEN[_]004|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupoActiva AND asignatura = @aVig AND periodoAcademico = @perFut)
       OR @@TRANCOUNT <> 1
        THROW 57418, 'TEST FAILED: HU074_18 crear grupo con una asignatura activa debe insertar (GEN_004) sin cerrar la transaccion del llamador.', 1;
    PRINT 'TEST_PASS:HU074_18_CREAR_GRUPO_ACTIVA';

    -- Desde aqui @aLibre queda inactiva
    UPDATE dbo.Asignatura SET estado = 0 WHERE id = @aLibre;

    -- HU074_07: crear grupo con una asignatura inactiva -> ASI_010
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @grupoNuevo, @idAsignatura = @aLibre, @idPeriodoAcademico = @perVig, @codigo = @codGrupoNuevo,
        @nombre = N'QA HU074 Nuevo', @idDocente = @dD, @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]010|%'
                   AND mu = (SELECT contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_010'))
       OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupoNuevo)
        THROW 57407, 'TEST FAILED: HU074_07 crear grupo con una asignatura inactiva debe dar ASI_010 sin insertar.', 1;
    PRINT 'TEST_PASS:HU074_07_CREAR_GRUPO_INACTIVA';

    -- HU074_08: asociar una asignatura inactiva a otro plan del coordinador -> ASI_010
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @aLibre, @idPlanEstudio = @pl2, @semestreNumero = @numSemestre,
        @codigoCaracter = N'OBL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uC;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estado = 0 AND mt LIKE N'DBCODE=ASI[_]010|%')
       OR EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @aLibre AND semestrePlanEstudio = @spe2)
        THROW 57408, 'TEST FAILED: HU074_08 asociar una asignatura inactiva debe dar ASI_010 sin crear vinculo.', 1;
    PRINT 'TEST_PASS:HU074_08_ASOCIAR_PLAN_INACTIVA';

    -- HU074_09: la oferta de creacion de grupo del docente excluye la inactiva y conserva la activa
    DECLARE @od TABLE (idDocente UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(50), nombreAsignatura NVARCHAR(200), programas NVARCHAR(1000));
    INSERT INTO @od EXEC dbo.usp_consultar_oferta_creacion_grupo_docente @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM @od WHERE idAsignatura = @aLibre) OR NOT EXISTS (SELECT 1 FROM @od WHERE idAsignatura = @aVig)
        THROW 57409, 'TEST FAILED: HU074_09 la oferta del docente debe excluir la inactiva y ofrecer la activa.', 1;
    PRINT 'TEST_PASS:HU074_09_OFERTA_EXCLUYE_INACTIVA';

    -- HU074_10: las asignaturas asociables al plan 2 excluyen la inactiva y conservan la activa
    DECLARE @as TABLE (idAsignatura UNIQUEIDENTIFIER, codigo NVARCHAR(50), nombre NVARCHAR(200), credito INT, nombreArea NVARCHAR(200),
        nombreComponente NVARCHAR(200), planes NVARCHAR(1000), totalRegistros INT);
    INSERT INTO @as EXEC dbo.usp_consultar_asignaturas_asociables_paginado @idUsuarioEjecutor = @uC, @idCorrelacion = @corr, @idPlanEstudio = @pl2,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'QA HU074';
    IF EXISTS (SELECT 1 FROM @as WHERE idAsignatura = @aLibre) OR NOT EXISTS (SELECT 1 FROM @as WHERE idAsignatura = @aVig)
        THROW 57410, 'TEST FAILED: HU074_10 las asociables deben excluir la inactiva y ofrecer la activa.', 1;
    PRINT 'TEST_PASS:HU074_10_ASOCIABLES_EXCLUYE_INACTIVA';

    -- HU074_11: la malla del plan muestra la inactiva (el coordinador la ve para reactivarla)
    DECLARE @ma TABLE (idAsignatura UNIQUEIDENTIFIER, codigo NVARCHAR(50), nombre NVARCHAR(200), credito INT, idArea UNIQUEIDENTIFIER, nombreArea NVARCHAR(200),
        idComponente UNIQUEIDENTIFIER, nombreComponente NVARCHAR(200), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT, idPrograma UNIQUEIDENTIFIER,
        nombrePrograma NVARCHAR(200), idSemestrePlanEstudio UNIQUEIDENTIFIER, numeroSemestre INT, codigoSemestre NVARCHAR(50), codigoCaracter NVARCHAR(10),
        nombreCaracter NVARCHAR(100), estaActivoVinculo BIT, estaActivaAsignatura BIT, compartida BIT, totalRegistros INT);
    INSERT INTO @ma EXEC dbo.usp_consultar_asignaturas_plan_paginado @idUsuarioEjecutor = @uC, @idCorrelacion = @corr, @idPlanEstudio = @pl1,
        @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM @ma WHERE idAsignatura = @aLibre AND estaActivaAsignatura = 0)
       OR NOT EXISTS (SELECT 1 FROM @ma WHERE idAsignatura = @aVig AND estaActivaAsignatura = 1)
        THROW 57411, 'TEST FAILED: HU074_11 la malla debe mostrar la inactiva con estaActivaAsignatura = 0.', 1;
    PRINT 'TEST_PASS:HU074_11_MALLA_MUESTRA_INACTIVA';

    IF @@TRANCOUNT <> 1 THROW 57498, 'TEST FAILED: HU074 alteraron el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #r;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

DROP TABLE IF EXISTS #r;
IF @@TRANCOUNT <> 0 THROW 57499, 'TEST FAILED: test_hu074_estado_asignatura dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:HU074_TRANCOUNT_ZERO';
PRINT 'TEST END: test_hu074_estado_asignatura';
GO
