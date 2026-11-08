USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- CULM-001 C.1 (CONTRACT §2.13.1 C-DB-01..13, C-DB-15, C-DB-63): motor de alertas de inasistencia por horas, consulta del estudiante
-- y paridad de programas. Todo dentro de una transaccion revertida; deja @@TRANCOUNT = 0.
PRINT 'TEST START: test_culm001_c_alertas';
IF OBJECT_ID(N'tempdb..#c1_faltas') IS NOT NULL DROP PROCEDURE #c1_faltas;
GO
CREATE PROCEDURE #c1_faltas @eg UNIQUEIDENTIFIER, @k INT, @codigo NVARCHAR(5) = N'SJC'
AS
BEGIN
    UPDATE da SET asistio = IIF(s.n <= @k AND @codigo <> N'EX', 0, IIF(s.n <= @k, 0, 1)),
                  razonCausa = (SELECT id FROM dbo.RazonCausa WHERE codigo = IIF(s.n <= @k, @codigo, N'AN'))
    FROM dbo.DetalleAsistencia da
    INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
    INNER JOIN #c1s s ON s.idSesion = a.sesion
    WHERE a.estudianteGrupo = @eg;
END;
GO
IF OBJECT_ID(N'tempdb..#c1_eval') IS NOT NULL DROP PROCEDURE #c1_eval;
GO
CREATE PROCEDURE #c1_eval @grupo UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER, @eg UNIQUEIDENTIFIER = NULL
AS
BEGIN
    DELETE FROM #c1ev;
    INSERT INTO #c1ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idEstudianteGrupo = @eg;
END;
GO
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_fixture.sql
    IF OBJECT_ID(N'tempdb..#c1ev') IS NOT NULL DROP TABLE #c1ev;
    CREATE TABLE #c1ev (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        alertasCreadas INT, alertasSuperadas INT, alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));
    DECLARE @n INT, @s INT;

    -- C-DB-02: bajo el umbral (3 faltas = 12 %): 0 alertas
    EXEC #c1_faltas @egEA, 3;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT estadoResultado FROM #c1ev) <> 1 OR (SELECT alertasCreadas FROM #c1ev) <> 0 OR EXISTS (SELECT 1 FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @egEA)
        THROW 58010, 'TEST FAILED: C-DB-02 12 % no debe generar alertas.', 1;

    -- C-DB-01: cruce de advertencia una sola vez (4 faltas = 16 %)
    EXEC #c1_faltas @egEA, 4;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasCreadas FROM #c1ev) <> 1 OR (SELECT revisionesCreadas FROM #c1ev) <> 0
       OR (SELECT COUNT(*) FROM OPENJSON((SELECT novedadesJSON FROM #c1ev)) WITH (esPrincipal BIT '$.esPrincipal', codigoTipo NVARCHAR(20) '$.codigoTipo') WHERE esPrincipal = 1 AND codigoTipo = N'ADVERTENCIA') <> 1
        THROW 58011, 'TEST FAILED: C-DB-01 el cruce del 16 % debe crear 1 alerta ADVERTENCIA principal.', 1;
    EXEC #c1_eval @grupoG, @c;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasCreadas FROM #c1ev) <> 0 OR (SELECT novedadesJSON FROM #c1ev) <> N'[]'
       OR (SELECT COUNT(*) FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @egEA) <> 1
        THROW 58012, 'TEST FAILED: C-DB-01 la segunda y tercera evaluacion no deben crear ni notificar de nuevo.', 1;

    -- C-DB-12: auditoria del motor (SYSTEM, correlacion)
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'ALERTA_INASISTENCIA_REGISTRADA' AND actorType = 'SYSTEM' AND ISJSON(metadata) = 1)
        THROW 58013, 'TEST FAILED: C-DB-12 falta la auditoria ALERTA_INASISTENCIA_REGISTRADA del motor.', 1;

    -- C-DB-07: superada (3 faltas = 12 %) y reactivada (4 = 16 %) sin novedad, ambas auditadas
    EXEC #c1_faltas @egEA, 3;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasSuperadas FROM #c1ev) <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_alerta_inasistencia WHERE idEstudianteGrupo = @egEA AND codigoTipo = N'ADVERTENCIA' AND codigoEstado = N'SUPERADA')
        THROW 58014, 'TEST FAILED: C-DB-07 al bajar del umbral la alerta debe quedar SUPERADA.', 1;
    EXEC #c1_faltas @egEA, 4;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasReactivadas FROM #c1ev) <> 1 OR (SELECT alertasCreadas FROM #c1ev) <> 0 OR (SELECT novedadesJSON FROM #c1ev) <> N'[]'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_alerta_inasistencia WHERE idEstudianteGrupo = @egEA AND codigoTipo = N'ADVERTENCIA' AND codigoEstado = N'VIGENTE')
       OR (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'ALERTA_INASISTENCIA_ACTUALIZADA') < 2
        THROW 58015, 'TEST FAILED: C-DB-07 la reactivacion no debe notificar y cada cambio de estado se audita.', 1;

    -- C-DB-06: salto directo de 16 % a 36 %: PERDIDA nueva, 1 revision, principal solo PERDIDA
    EXEC #c1_faltas @egEA, 9;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasCreadas FROM #c1ev) <> 1 OR (SELECT revisionesCreadas FROM #c1ev) <> 1
       OR NOT EXISTS (SELECT 1 FROM OPENJSON((SELECT novedadesJSON FROM #c1ev)) WITH (esPrincipal BIT '$.esPrincipal', codigoTipo NVARCHAR(20) '$.codigoTipo') WHERE esPrincipal = 1 AND codigoTipo = N'PERDIDA')
        THROW 58016, 'TEST FAILED: C-DB-06 el cruce a perdida debe crear la alerta, la revision y marcarla principal.', 1;
    SELECT @n = COUNT(*) FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egEA;
    IF @n <> 1 OR (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial h INNER JOIN dbo.RevisionCancelacion r ON r.id = h.revision WHERE r.estudianteGrupo = @egEA AND h.codigoEvento = N'CREAR') <> 1
        THROW 58017, 'TEST FAILED: C-DB-06/12 debe existir 1 revision con 1 historial CREAR.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'REVISION_CANCELACION_CREADA' AND actorType = 'SYSTEM')
        THROW 58018, 'TEST FAILED: C-DB-12 falta la auditoria REVISION_CANCELACION_CREADA.', 1;

    -- C-DB-03: EX no cuenta (EB: 6 h EX = 24 % sin alertas); EX -> SJC la cuenta
    EXEC #c1_faltas @egEB, 6, N'EX';
    EXEC #c1_eval @grupoG, @c, @egEB;
    IF EXISTS (SELECT 1 FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @egEB)
        THROW 58019, 'TEST FAILED: C-DB-03 las excusas (EX) no deben contar para las alertas.', 1;
    EXEC #c1_faltas @egEB, 6, N'SJC';
    EXEC #c1_eval @grupoG, @c, @egEB;
    IF (SELECT COUNT(*) FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @egEB) <> 2
        THROW 58020, 'TEST FAILED: C-DB-03 con SJC deben existir ADVERTENCIA y PERDIDA.', 1;

    -- C-DB-10: @idEstudianteGrupo de otro grupo -> ALR_006; filtra solo esa matricula
    DECLARE @otroEg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstudianteGrupo WHERE grupo <> @grupoG);
    IF @otroEg IS NOT NULL
    BEGIN
        EXEC #c1_eval @grupoG, @c, @otroEg;
        IF (SELECT estadoResultado FROM #c1ev) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1ev) NOT LIKE N'%ALR_006%'
            THROW 58021, 'TEST FAILED: C-DB-10 una matricula de otro grupo debe dar ALR_006.', 1;
    END

    -- C-DB-08: solo matriculas A (E0 en CI con 30 %: 0 alertas)
    EXEC #c1_faltas @eg0, 8;
    UPDATE dbo.EstudianteGrupo SET estado = @estCI WHERE id = @eg0;
    EXEC #c1_eval @grupoG, @c, @eg0;
    IF EXISTS (SELECT 1 FROM dbo.AlertaInasistencia WHERE estudianteGrupo = @eg0)
        THROW 58022, 'TEST FAILED: C-DB-08 una matricula en CI no debe generar alertas.', 1;
    UPDATE dbo.EstudianteGrupo SET estado = @estA WHERE id = @eg0;

    -- C-DB-09: interruptor y umbral
    UPDATE dbo.CatalogoParametro SET valor = N'false' WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';
    DECLARE @antes INT = (SELECT COUNT(*) FROM dbo.AlertaInasistencia);
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT estadoResultado FROM #c1ev) <> 1 OR (SELECT mensajeTecnicoResultado FROM #c1ev) NOT LIKE N'%ALR_001%' OR (SELECT COUNT(*) FROM dbo.AlertaInasistencia) <> @antes
        THROW 58023, 'TEST FAILED: C-DB-09 con el motor deshabilitado responde ALR_001 sin escribir.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'true' WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';
    UPDATE dbo.CatalogoParametro SET valor = N'x' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT estadoResultado FROM #c1ev) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1ev) NOT LIKE N'%ALR_002%' OR (SELECT COUNT(*) FROM dbo.AlertaInasistencia) <> @antes
        THROW 58024, 'TEST FAILED: C-DB-09 con umbral no numerico responde ALR_002 sin escribir.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'20' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';

    -- C-DB-13: transaccion externa (savepoint; no destruye la del llamador)
    IF @@TRANCOUNT <> 1 THROW 58025, 'TEST FAILED: C-DB-13 el motor destruyo la transaccion externa.', 1;

    -- C-DB-15: consulta del estudiante EA: solo propias, columnas sin revision, soloVigentes, grupo ajeno -> SEC_002
    IF OBJECT_ID(N'tempdb..#c1al') IS NOT NULL DROP TABLE #c1al;
    CREATE TABLE #c1al (id UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400),
        idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
        idPeriodoAcademico UNIQUEIDENTIFIER, codigoEstadoMatricula NVARCHAR(50), idTipo UNIQUEIDENTIFIER, codigoTipo NVARCHAR(20), nombreTipo NVARCHAR(50), nivel TINYINT,
        codigoMensajeUsuario VARCHAR(100), idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), estaVigente BIT, porcentajeCruce DECIMAL(5,2), umbralCruce DECIMAL(5,2),
        horasFaltaCruce DECIMAL(12,6), horasDictadasCruce DECIMAL(12,6), fechaCruceUtc DATETIME2(3), porcentajeUltimaEvaluacion DECIMAL(5,2),
        fechaUltimaEvaluacionUtc DATETIME2(3), fechaLecturaUtc DATETIME2(3), estaLeida BIT, porcentajeActual DECIMAL(5,2), umbralPerdidaActual DECIMAL(5,2), totalRegistros INT);
    DECLARE @uEA2 UNIQUEIDENTIFIER = @uEA;
    INSERT INTO #c1al EXEC dbo.usp_consultar_alertas_estudiante @idUsuarioEjecutor = @uEA2, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 20, @soloNoLeidas = 0, @soloVigentes = 0, @idGrupo = NULL;
    IF (SELECT COUNT(*) FROM #c1al) <> 2 OR EXISTS (SELECT 1 FROM #c1al WHERE idEstudianteGrupo <> @egEA) OR (SELECT MAX(totalRegistros) FROM #c1al) <> 2
        THROW 58026, 'TEST FAILED: C-DB-15 el estudiante solo ve sus 2 alertas.', 1;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'tempdb..#c1al') AND name IN (N'codigoEstadoRevision', N'idUsuarioEstudiante', N'idDocenteTitular'))
        THROW 58027, 'TEST FAILED: C-DB-15 (plantilla de columnas).', 1;
    DELETE FROM #c1al;
    EXEC #c1_faltas @egEA, 3;
    EXEC #c1_eval @grupoG, @c;
    INSERT INTO #c1al EXEC dbo.usp_consultar_alertas_estudiante @idUsuarioEjecutor = @uEA2, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 1, @soloNoLeidas = 0, @soloVigentes = 1, @idGrupo = NULL;
    IF (SELECT MAX(totalRegistros) FROM #c1al) IS NOT NULL AND (SELECT MAX(totalRegistros) FROM #c1al) <> 0
        THROW 58028, 'TEST FAILED: C-DB-15 con 12 % las alertas pasan a SUPERADA y soloVigentes no cuenta ninguna.', 1;
    DECLARE @gAjeno BIT = 0;
    BEGIN TRY
        INSERT INTO #c1al EXEC dbo.usp_consultar_alertas_estudiante @idUsuarioEjecutor = @uEA2, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 20, @soloNoLeidas = 0, @soloVigentes = 0, @idGrupo = '00000000-0000-0000-0000-0000000000AA';
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%SEC_002%' SET @gAjeno = 1;
    END CATCH
    IF @gAjeno = 0 THROW 58029, 'TEST FAILED: C-DB-15 un grupo ajeno debe dar SEC_002.', 1;

    -- C-DB-63: paridad de programas competentes con EstudiantePrograma INTERSECT ufn_programas_grupo para todas las matriculas
    IF EXISTS (
        SELECT 1 FROM dbo.EstudianteGrupo eg
        CROSS APPLY (
            SELECT p = COUNT(*) FROM (SELECT DISTINCT idPrograma FROM dbo.ufn_revision_cancelacion_resolutores(eg.id, NULL)) f
        ) fn
        CROSS APPLY (
            SELECT p = COUNT(*) FROM dbo.EstudiantePrograma ep INNER JOIN dbo.ufn_programas_grupo(eg.grupo) pg ON pg.idPrograma = ep.programa
                INNER JOIN dbo.Programa pr ON pr.id = pg.idPrograma AND pr.estado = 1 INNER JOIN dbo.Coordinador co ON co.id = pr.coordinador AND co.estado = 1
            WHERE ep.estudiante = eg.estudiante
        ) ex
        WHERE eg.grupo = @grupoG AND fn.p <> ex.p AND EXISTS (SELECT 1 FROM dbo.ufn_revision_cancelacion_resolutores(eg.id, NULL) WHERE esEscalamiento = 0)
    )
        THROW 58030, 'TEST FAILED: C-DB-63 los programas competentes difieren de EstudiantePrograma INTERSECT ufn_programas_grupo.', 1;

    PRINT 'TEST_PASS:CULM001_C_ALERTAS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58099, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58098, 'TEST FAILED: C alertas dejo una transaccion abierta.', 1;
GO
