USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Regla (John, 2026-10-29): un docente no puede tener dos grupos a la misma hora.
-- usp_actualizar_grupo valida con usp_validar_cruce_horario_docente_interno cuando cambia el titular (HOR_002):
-- mismo dia y periodo con franjas que se traslapan. Las horas contiguas, otro dia u otro periodo no son cruce.
PRINT 'TEST START: test_cruce_horario_docente';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.PeriodoAcademico WHERE id = @idPeriodo);
DECLARE @lunes UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Dia WHERE nombre = N'Lunes');
DECLARE @martes UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Dia WHERE nombre = N'Martes');
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
IF @tipoCC IS NULL OR @idAsig IS NULL OR @uCoord IS NULL OR @idPeriodo IS NULL OR @idInstitucion IS NULL
   OR @lunes IS NULL OR @martes IS NULL OR @tvCat IS NULL
    THROW 53100, 'TEST FAILED: faltan fixtures del seed (asignatura, coordinador, periodo, dias o vinculacion).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD1 UNIQUEIDENTIFIER = NEWID(), @uD2 UNIQUEIDENTIFIER = NEWID(), @d1 UNIQUEIDENTIFIER = NEWID(), @d2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD1, @tipoCC, 971000001, N'Cruce', N'Uno', N'Daniel', N'Qa', N'qa.cruce.d1@test.local', 1, 1, N'HashBackend_C1'),
           (@uD2, @tipoCC, 971000002, N'Cruce', N'Dos', N'Debora', N'Qa', N'qa.cruce.d2@test.local', 1, 1, N'HashBackend_C2');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d1, @uD1), (@d2, @uD2);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d1, @idProg, @tvCat, 1, SYSUTCDATETIME()), (NEWID(), @d2, @idProg, @tvCat, 1, SYSUTCDATETIME());

    -- Otro periodo (sin grupos) para el caso "mismo horario en otro periodo"
    DECLARE @idPeriodoOtro UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idPeriodoOtro, @idInstitucion, N'Periodo QA cruce', 97, '2099-01-15', '2099-06-15', 2099);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @base INT = 70000 + ABS(CHECKSUM(NEWID()) % 9000);
    DECLARE @gA UNIQUEIDENTIFIER = NEWID(), @gB UNIQUEIDENTIFIER = NEWID(), @gC UNIQUEIDENTIFIER = NEWID(),
            @gD UNIQUEIDENTIFIER = NEWID(), @gE UNIQUEIDENTIFIER = NEWID();
    DECLARE @codA INT = @base, @codB INT = @base + 1, @codC INT = @base + 2, @codD INT = @base + 3, @codE INT = @base + 4;

    -- Grupos: A del docente 1; B, C, D (periodo vigente) y E (otro periodo) del docente 2.
    -- Crear grupo no puede cruzar: el grupo nace sin horario (Horario.grupo es FK a Grupo).
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gA, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codA,
        @nombre = N'Grupo QA Cruce A', @idDocente = @d1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gB, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codB,
        @nombre = N'Grupo QA Cruce B', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gC, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codC,
        @nombre = N'Grupo QA Cruce C', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gD, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = @codD,
        @nombre = N'Grupo QA Cruce D', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @gE, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodoOtro, @codigo = @codE,
        @nombre = N'Grupo QA Cruce E', @idDocente = @d2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 5 THROW 53101, 'TEACHER_SCHEDULE_CREATE_ALLOWED FAILED: los 5 grupos debieron crearse.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_CREATE_ALLOWED';

    -- Horarios (no hay SP que los escriba: hoy solo vienen de los seeds)
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @gA, @lunes,  '08:00', '10:00'),
           (NEWID(), @gB, @lunes,  '09:00', '11:00'),   -- se traslapa con A
           (NEWID(), @gC, @lunes,  '10:00', '12:00'),   -- contigua a A
           (NEWID(), @gD, @martes, '08:00', '10:00'),   -- otro dia
           (NEWID(), @gE, @lunes,  '08:00', '10:00');   -- otro periodo

    -- 1. Cruce: B no puede pasar al docente 1 (ya tiene A el lunes de 08:00 a 10:00)
    DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'HOR_002', @p_param1 = N'Grupo QA Cruce A', @p_param2 = N'Lunes 08:00-10:00',
        @p_param3 = @gB, @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo @idGrupo = @gB, @codigo = NULL, @nombre = NULL, @idDocente = @d1, @cupoMaximo = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
                   AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr))
        THROW 53110, 'TEACHER_SCHEDULE_CONFLICT_REJECTED FAILED: debio retornar HOR_002 con el grupo y la franja.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gB AND docente = @d2)
        THROW 53111, 'TEACHER_SCHEDULE_CONFLICT_REJECTED FAILED: el titular de B cambio pese al cruce.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_CONFLICT_REJECTED';

    -- 2. Horas contiguas (10:00-12:00 contra 08:00-10:00): permitido
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo @idGrupo = @gC, @codigo = NULL, @nombre = NULL, @idDocente = @d1, @cupoMaximo = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gC AND docente = @d1)
        THROW 53120, 'TEACHER_SCHEDULE_ADJACENT_ALLOWED FAILED: las horas contiguas no son cruce.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_ADJACENT_ALLOWED';

    -- 3. Mismo horario otro dia: permitido
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo @idGrupo = @gD, @codigo = NULL, @nombre = NULL, @idDocente = @d1, @cupoMaximo = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gD AND docente = @d1)
        THROW 53130, 'TEACHER_SCHEDULE_OTHER_DAY_ALLOWED FAILED: otro dia no es cruce.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_OTHER_DAY_ALLOWED';

    -- 4. Mismo dia y franja en otro periodo: permitido
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo @idGrupo = @gE, @codigo = NULL, @nombre = NULL, @idDocente = @d1, @cupoMaximo = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gE AND docente = @d1)
        THROW 53140, 'TEACHER_SCHEDULE_OTHER_PERIOD_ALLOWED FAILED: otro periodo no es cruce.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_OTHER_PERIOD_ALLOWED';

    -- 5. Sin cambio de titular no se revalida: editar el cupo de A (docente 1) sigue permitido
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_grupo @idGrupo = @gA, @codigo = NULL, @nombre = NULL, @idDocente = @d1, @cupoMaximo = 45,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gA AND cantidadEstudiantes = 45)
        THROW 53150, 'TEACHER_SCHEDULE_SAME_TITULAR_ALLOWED FAILED: editar sin cambiar el titular debio permitirse.', 1;
    PRINT 'TEST_PASS:TEACHER_SCHEDULE_SAME_TITULAR_ALLOWED';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id IN (@gA, @gB, @gC, @gD, @gE)) THROW 53160, 'TEST FAILED: quedaron grupos de prueba.', 1;
    IF @@TRANCOUNT <> 0 THROW 53161, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST END: test_cruce_horario_docente';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 53199, @err, 1;
END CATCH
GO
