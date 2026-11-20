USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- SES-GEN-01 (migracion 59): calendario de sesiones del semestre al definir el grupo.
--   SES_01_PER_CALC     usp_crear_periodo_academico sin fechaFin: fin = inicio + 16 semanas - 1 dia (112 dias)
--   SES_02_PER_RECHAZO  fechaFin que no mide 112 dias -> PER_011; fechaFin correcta -> exito
--   SES_03_PER_EDIT     usp_actualizar_periodo_academico: solo cambia el nombre -> no valida la duracion; cambia fechas -> PER_011
--   SES_04_B2B          precarga en un periodo que inicia a mitad de semana: 1 franja = 16 sesiones, 2 franjas = 32, numeroSemana 1..16
--   SES_05_B5           suma semanal de las franjas igual, exacta, a horasSemanales * 60 (HOR_006); NULL no valida
--   SES_06_B7           duracion de la franja (HOR_007) y ventana horaria (HOR_008)
--   SES_07_PREVIEW      usp_previsualizar_horario_grupo: grupo nuevo = mismas sesiones que la precarga de la confirmacion; conflictos como datos
--   SES_08_B1_B2        usp_crear_grupo: periodo terminado -> PER_010; asignatura sin vinculo activo -> ASI_014
--   SES_09_ASI_013      usp_actualizar_asignatura: horasSemanales fuera de rango -> ASI_013
-- Todo corre en UNA transaccion con ROLLBACK final.
-- ============================================================================
IF OBJECT_ID('tempdb..#ses_expect') IS NOT NULL DROP PROCEDURE #ses_expect;
GO
CREATE PROCEDURE #ses_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: SES_GEN_01_', @label);
        THROW 52970, @mensaje, 1;
    END
END;
GO

DECLARE @uAdmin UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @asignatura UNIQUEIDENTIFIER, @docente UNIQUEIDENTIFIER;
-- Un coordinador, una asignatura activa con vinculo activo cuyos programas coordina por completo, y un docente con grupo en esa asignatura
SELECT TOP 1 @uCoord = c.usuario, @asignatura = g.idAsignatura, @docente = g.idDocente
FROM dbo.Coordinador c
INNER JOIN dbo.Programa p ON p.coordinador = c.id
INNER JOIN dbo.uv_asignatura_plan_estudio v ON v.idPrograma = p.id AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1 AND v.estaActivaAsignatura = 1
INNER JOIN dbo.uv_grupo g ON g.idAsignatura = v.idAsignatura
WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v2
                  WHERE v2.idAsignatura = v.idAsignatura AND v2.estaActivoVinculo = 1 AND v2.estaActivoPlan = 1
                    AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(c.usuario) cp WHERE cp.idPrograma = v2.idPrograma))
ORDER BY c.id;
SELECT TOP 1 @uAdmin = a.usuario
FROM dbo.Administrador a
INNER JOIN dbo.uv_programa p ON p.idInstitucion = a.institucion
INNER JOIN dbo.Coordinador c ON c.usuario = @uCoord
WHERE p.idCoordinador = c.id
ORDER BY a.id;
IF @uAdmin IS NULL OR @uCoord IS NULL OR @asignatura IS NULL OR @docente IS NULL
    THROW 52971, 'TEST FAILED: SES_GEN_01 faltan fixtures del seed (administrador, coordinador, asignatura o docente).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @err NVARCHAR(4000), @n INT, @codigo NVARCHAR(60);
DECLARE @per UNIQUEIDENTIFIER = NEWID(), @per2 UNIQUEIDENTIFIER = NEWID(), @perViejo UNIQUEIDENTIFIER = NEWID();
DECLARE @grupo UNIQUEIDENTIFIER = NEWID(), @grupo2 UNIQUEIDENTIFIER = NEWID(), @grupo3 UNIQUEIDENTIFIER = NEWID();
DECLARE @inicio DATE = DATEADD(DAY, 60, CAST(SYSUTCDATETIME() AS DATE));
-- El periodo debe iniciar a mitad de semana (miercoles) para probar que numeroSemana no depende del primer dia de la semana
WHILE DATEDIFF(DAY, '19000101', @inicio) % 7 <> 2 SET @inicio = DATEADD(DAY, 1, @inicio);
DECLARE @fin DATE = DATEADD(DAY, 111, @inicio);
DECLARE @finMal DATE = DATEADD(DAY, 30, @fin);
DECLARE @h1 NVARCHAR(MAX) = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"12:00"}]';
DECLARE @h2 NVARCHAR(MAX) = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"MI","horaInicio":"08:00","horaFin":"10:00"}]';

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT, idPeriodo UNIQUEIDENTIFIER NULL);
CREATE TABLE #r4 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #pv (tipoFila VARCHAR(12), orden INT, id1 UNIQUEIDENTIFIER, id2 UNIQUEIDENTIFIER, id3 UNIQUEIDENTIFIER,
    texto1 NVARCHAR(200), texto2 NVARCHAR(200), texto3 NVARCHAR(4000), texto4 NVARCHAR(200), texto5 NVARCHAR(200),
    fecha1 DATE, fecha2 DATE, instante1 DATETIME2, instante2 DATETIME2,
    e1 INT, e2 INT, e3 INT, e4 INT, e5 INT, e6 INT, e7 INT, e8 INT, e9 INT, e10 INT, e11 INT, e12 INT, e13 INT, e14 INT, e15 INT, e16 INT, e17 INT, e18 INT,
    b1 BIT, b2 BIT);

BEGIN TRY
    BEGIN TRANSACTION;

    -- ---------------------------------------------------------------- SES_01 el fin se calcula
    INSERT #r EXEC dbo.usp_crear_periodo_academico @idPeriodo = @per, @nombre = N'SES-GEN-01 A', @fechaInicio = @inicio, @fechaFin = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per AND fechaInicio = @inicio AND fechaFin = @fin AND DATEDIFF(DAY, fechaInicio, fechaFin) + 1 = 112), 1, 0);
    EXEC #ses_expect 'SES_01_PER_CALC', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_PER_CALC';

    -- ---------------------------------------------------------------- SES_02 duracion exacta
    DELETE #r;
    INSERT #r EXEC dbo.usp_crear_periodo_academico @idPeriodo = @per2, @nombre = N'SES-GEN-01 B', @fechaInicio = @inicio, @fechaFin = @finMal,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_011%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @per2), 1, 0);
    EXEC #ses_expect 'SES_02_PER_RECHAZO', @ok;
    DELETE #r;
    INSERT #r EXEC dbo.usp_crear_periodo_academico @idPeriodo = @per2, @nombre = N'SES-GEN-01 B', @fechaInicio = @inicio, @fechaFin = @fin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1), 1, 0);
    EXEC #ses_expect 'SES_02_PER_FIN_CORRECTO', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_PER_RECHAZO';

    -- ---------------------------------------------------------------- SES_03 edicion: solo valida si cambian las fechas
    -- Periodo historico de 137 dias (no cumple la regla): se conserva y solo cambia de nombre
    DELETE #r;
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    SELECT @perViejo, institucion, N'SES-GEN-01 historico', 99991, DATEADD(DAY, -400, @inicio), DATEADD(DAY, -264, @inicio), YEAR(DATEADD(DAY, -400, @inicio))
    FROM dbo.PeriodoAcademico WHERE id = @per;
    DECLARE @iniViejo DATETIME2, @finViejo DATETIME2;
    SELECT @iniViejo = fechaInicio, @finViejo = fechaFin FROM dbo.PeriodoAcademico WHERE id = @perViejo;
    INSERT #r4 EXEC dbo.usp_actualizar_periodo_academico @idPeriodo = @perViejo, @nombre = N'SES-GEN-01 historico renombrado',
        @fechaInicio = @iniViejo, @fechaFin = @finViejo, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #ses_expect 'SES_03_PER_EDIT_SOLO_NOMBRE', @ok;
    DELETE #r4;
    DECLARE @finEditado DATETIME2 = DATEADD(DAY, -200, @inicio);
    INSERT #r4 EXEC dbo.usp_actualizar_periodo_academico @idPeriodo = @perViejo, @nombre = N'SES-GEN-01 historico renombrado',
        @fechaInicio = @iniViejo, @fechaFin = @finEditado, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_011%'), 1, 0);
    EXEC #ses_expect 'SES_03_PER_EDIT_FECHAS', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_PER_EDIT';

    -- ---------------------------------------------------------------- Fixture de grupos para B2b, B5, B7 y la previsualizacion
    UPDATE dbo.Asignatura SET horasSemanales = 4 WHERE id = @asignatura;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @grupo, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @codigo = 987, @nombre = N'SES-GEN-01 g1',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #ses_expect 'SES_FIXTURE_GRUPO', @ok;

    -- ---------------------------------------------------------------- SES_08 B1: sin vinculo activo a plan activo -> ASI_014 (la asignatura sigue activa)
    DECLARE @vinculosActivos TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);
    INSERT @vinculosActivos (id)
    SELECT id FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asignatura AND estaActivo = 1;
    UPDATE dbo.AsignaturaPlanEstudio
    SET estaActivo = 0, fechaDesvinculacionUtc = DATEADD(MILLISECOND, 1, fechaVinculacionUtc)
    WHERE id IN (SELECT id FROM @vinculosActivos);
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @grupo3, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @codigo = 989, @nombre = N'SES-GEN-01 g3',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ASI_014%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo3)
                  AND EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @asignatura AND estaActivaAsignatura = 1), 1, 0);
    UPDATE dbo.AsignaturaPlanEstudio
    SET estaActivo = 1, fechaDesvinculacionUtc = NULL
    WHERE id IN (SELECT id FROM @vinculosActivos);
    EXEC #ses_expect 'SES_08_B1_SIN_VINCULO_ASI_014', @ok;

    -- ---------------------------------------------------------------- SES_08 B2: periodo terminado -> PER_010 (sin sustitucion silenciosa)
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @grupo2, @idAsignatura = @asignatura, @idPeriodoAcademico = @perViejo, @codigo = 988, @nombre = N'SES-GEN-01 g2',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_010%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo2), 1, 0);
    EXEC #ses_expect 'SES_08_B2_PERIODO_TERMINADO', @ok;
    -- DEC-076 + DR-06: un id informado inexistente nunca se sustituye (VAL_002); NULL pide el periodo en curso (ACTIVO mas reciente o
    -- proximo en PLANEACION) y ese periodo tambien pasa por la validacion de vigencia/institucion (PASO 3B).
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @grupo2, @idAsignatura = @asignatura, @idPeriodoAcademico = @grupo2, @codigo = 988, @nombre = N'SES-GEN-01 g2',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=VAL_002%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo2), 1, 0);
    EXEC #ses_expect 'SES_08_B2_ID_INEXISTENTE_NO_SUSTITUYE', @ok;
    DECLARE @perEnCurso UNIQUEIDENTIFIER =
        COALESCE((SELECT TOP (1) id FROM dbo.uv_periodo_academico WHERE estado = 'ACTIVO' ORDER BY fechaInicio DESC, id),
                 (SELECT TOP (1) id FROM dbo.uv_periodo_academico WHERE estado = 'PLANEACION' ORDER BY fechaInicio ASC, id));
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @grupo2, @idAsignatura = @asignatura, @idPeriodoAcademico = NULL, @codigo = 988, @nombre = N'SES-GEN-01 g2',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(@perEnCurso IS NOT NULL
                  AND ((EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1)
                        AND EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo2 AND periodoAcademico = @perEnCurso))
                    OR (EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_010%')
                        AND NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo2))), 1, 0);
    EXEC #ses_expect 'SES_08_B2_NULL_PERIODO_EN_CURSO', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_B1_B2';

    -- ---------------------------------------------------------------- SES_05 B5: 4 h semanales exactas
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=HOR_006%')
                  AND NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = @grupo), 1, 0);
    EXEC #ses_expect 'SES_05_B5_2H_DE_4H', @ok;
    -- B7: 4 h en una sola franja supera la duracion maxima de 240 min? No: 240 = 4 h exacto, se permite
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = @h1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #ses_expect 'SES_05_B5_4H_EN_1_FRANJA', @ok;
    -- 2 franjas de 2 h = 4 h
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1) AND (SELECT COUNT(*) FROM dbo.Horario WHERE grupo = @grupo) = 2, 1, 0);
    EXEC #ses_expect 'SES_05_B5_2_FRANJAS_DE_2H', @ok;
    -- materia sin horas (NULL): no se valida
    UPDATE dbo.Asignatura SET horasSemanales = NULL WHERE id = @asignatura;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #ses_expect 'SES_05_B5_MATERIA_SIN_HORAS', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_B5';

    -- ---------------------------------------------------------------- SES_06 B7
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"08:30"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=HOR_007%'), 1, 0);
    EXEC #ses_expect 'SES_06_B7_DURACION', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"05:00","horaFin":"07:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=HOR_008%'), 1, 0);
    EXEC #ses_expect 'SES_06_B7_VENTANA', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_B7';

    -- ---------------------------------------------------------------- SES_04 B2b + SES_07 la previsualizacion coincide con la precarga
    UPDATE dbo.Asignatura SET horasSemanales = 4 WHERE id = @asignatura;
    -- (el horario guardado del grupo del docente se limpia: la previsualizacion de un grupo NUEVO no debe chocar con el suyo)
    DELETE FROM dbo.Horario WHERE grupo = @grupo;
    -- 2 franjas por semana en un periodo futuro de 112 dias que empieza a mitad de semana
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @idDocente = @docente,
        @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SELECT @n = e5 FROM #pv WHERE tipoFila = 'RESUMEN';
    SET @ok = IIF(@n = 32 AND (SELECT e4 FROM #pv WHERE tipoFila = 'RESUMEN') = 112
                  AND (SELECT b1 FROM #pv WHERE tipoFila = 'RESUMEN') = 1
                  AND (SELECT MAX(e2) FROM #pv WHERE tipoFila = 'SESION') = 16 AND (SELECT MIN(e2) FROM #pv WHERE tipoFila = 'SESION') = 1, 1, 0);
    EXEC #ses_expect 'SES_07_PREVIEW_32_SESIONES', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    DECLARE @cre INT, @eli INT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @okPre BIT;
    EXEC dbo.usp_precargar_sesiones_grupo_interno @idGrupo = @grupo, @idCorrelacion = @corr, @sesionesCreadas = @cre OUTPUT, @sesionesEliminadas = @eli OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okPre OUTPUT;
    SET @ok = IIF(@okPre = 1 AND @cre = @n AND (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grupo) = 32
                  AND (SELECT MAX(numeroSemana) FROM dbo.Sesion WHERE grupo = @grupo) = 16 AND (SELECT MIN(numeroSemana) FROM dbo.Sesion WHERE grupo = @grupo) = 1, 1, 0);
    EXEC #ses_expect 'SES_04_B2B_32_SESIONES_SEMANAS_1_16', @ok;
    -- 1 franja por semana = 16 sesiones
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @grupo, @horariosJSON = @h1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    EXEC dbo.usp_precargar_sesiones_grupo_interno @idGrupo = @grupo, @idCorrelacion = @corr, @sesionesCreadas = @cre OUTPUT, @sesionesEliminadas = @eli OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okPre OUTPUT;
    SET @ok = IIF(@okPre = 1 AND (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grupo AND fechaHoraInicio > SYSUTCDATETIME()) = 16
                  AND (SELECT MAX(numeroSemana) FROM dbo.Sesion WHERE grupo = @grupo) = 16, 1, 0);
    EXEC #ses_expect 'SES_04_B2B_16_SESIONES_1_FRANJA', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_B2B';
    -- La previsualizacion muestra el conflicto B5 como dato (200) en lugar de lanzar
    DELETE #pv;
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @idDocente = @docente,
        @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"}]', @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'CONFLICTO' AND texto1 = 'HOR_006' AND texto2 = 'BLOQUEANTE')
                  AND (SELECT b1 FROM #pv WHERE tipoFila = 'RESUMEN') = 0, 1, 0);
    EXEC #ses_expect 'SES_07_PREVIEW_CONFLICTO_B5', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_PREVIEW';

    -- ---------------------------------------------------------------- SES_09 ASI_013
    DECLARE @idPlan UNIQUEIDENTIFIER, @sem INT;
    SELECT TOP 1 @idPlan = v.idPlanEstudio, @sem = v.numeroSemestre
    FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = @asignatura AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
      AND v.idPrograma IN (SELECT idPrograma FROM dbo.ufn_programas_coordinador(@uCoord));
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asignatura, @codigo = NULL, @nombre = NULL, @creditos = NULL, @idPlanEstudio = @idPlan,
        @semestreNumero = @sem, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord, @horasSemanales = 99;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ASI_013%'), 1, 0);
    EXEC #ses_expect 'SES_09_ASI_013', @ok;
    PRINT 'TEST_PASS:SES_GEN_01_ASI_013';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 52979, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
