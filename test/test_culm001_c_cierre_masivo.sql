USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- CULM-001 C.1 (CONTRACT §2.13.1 C-DB-40, 41, 43, 44, 47; DEC-041 C-10, N-1): el cierre masivo ya no escribe CI por conteo: con el
-- motor activo se bloquea (RCN_012) si hay revisiones pendientes o perdidas sin revision (sin crear nada) y devuelve siempre una
-- sola fila; con el motor apagado o umbrales invalidos no bloquea y lo deja auditado. Transaccion revertida.
PRINT 'TEST START: test_culm001_c_cierre_masivo';
GO
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_cierre_fixture.sql
    IF OBJECT_ID(N'tempdb..#c1c') IS NOT NULL DROP TABLE #c1c;
    CREATE TABLE #c1c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    IF OBJECT_ID(N'tempdb..#c1ev') IS NOT NULL DROP TABLE #c1ev;
    CREATE TABLE #c1ev (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        alertasCreadas INT, alertasSuperadas INT, alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));
    IF OBJECT_ID(N'tempdb..#c1d') IS NOT NULL DROP TABLE #c1d;
    CREATE TABLE #c1d (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        idRevision UNIQUEIDENTIFIER, codigoEstadoAnterior NVARCHAR(20), codigoEstadoNuevo NVARCHAR(20), codigoDecision NVARCHAR(20), sinCambios BIT,
        idGrupo UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, porcentajeActual DECIMAL(5,2),
        tipoPlantillaNotificacion VARCHAR(60), codigoPerfilResolutor NVARCHAR(20), esEscalamiento BIT);
    DECLARE @mot NVARCHAR(100) = N'Motivo de prueba suficiente';

    -- C-DB-47 / C-DB-40: motor activo y 2 perdidas sin revision -> RCN_012 en UNA fila (INSERT ... EXEC), sin crear nada
    DELETE FROM #c1c;
    INSERT INTO #c1c (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
    EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT COUNT(*) FROM #c1c) <> 1 OR (SELECT estadoResultado FROM #c1c) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1c) NOT LIKE N'%RCN_012%'
        THROW 58310, 'TEST FAILED: C-DB-40/47 el cierre con 2 perdidas sin revision debe responder RCN_012 en una sola fila.', 1;
    IF EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo WHERE eg.grupo = @grupoC)
       OR EXISTS (SELECT 1 FROM dbo.AlertaInasistencia a INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo WHERE eg.grupo = @grupoC)
       OR EXISTS (SELECT 1 FROM dbo.EvaluacionAlertaGrupo WHERE grupo = @grupoC)
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupoC AND estado = @estAct) <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupoC AND cantidadEstudiantesFinalizaron = 0 AND cantidadEstudiantesCancelaronAutomaticamente = 0)
        THROW 58311, 'TEST FAILED: C-DB-40 el cierre bloqueado no crea revisiones ni escribe en alertas, evaluacion, matriculas o contadores (N-1).', 1;
    IF @@TRANCOUNT <> 1 THROW 58312, 'TEST FAILED: C-DB-40 el cierre destruyo la transaccion del llamador.', 1;
    IF EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d WHERE d.referencing_id = OBJECT_ID(N'dbo.usp_ejecutar_cierre_masivo_periodo') AND d.referenced_entity_name = N'usp_evaluar_alertas_inasistencia_grupo')
        THROW 58313, 'TEST FAILED: C-DB-47 el cierre no debe referenciar el motor.', 1;

    -- C-DB-40: con revisiones pendientes (motor ejecutado por el backend) tambien se bloquea
    INSERT INTO #c1ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @grupoC, @idCorrelacion = @corr, @idEstudianteGrupo = NULL;
    IF (SELECT revisionesCreadas FROM #c1ev) <> 2 THROW 58314, 'TEST FAILED: C-DB-40 el motor debe crear 2 revisiones.', 1;
    DELETE FROM #c1c;
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT estadoResultado FROM #c1c) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1c) NOT LIKE N'%RCN_012%'
        THROW 58315, 'TEST FAILED: C-DB-40 con revisiones PENDIENTE_DOCENTE el cierre responde RCN_012.', 1;

    -- C-DB-41: el docente mantiene a uno y propone al otro; el coordinador aprueba: el cierre deja F (mantenido, presente) y CI (aprobada)
    DECLARE @rev1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egAbs1);
    DECLARE @rev2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egAbs2);
    DELETE FROM #c1d;
    INSERT INTO #c1d EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev1, @codigoDecision = N'MANTENER', @motivo = @mot, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocC;
    IF (SELECT estadoResultado FROM #c1d) <> 1 THROW 58316, 'TEST FAILED: C-DB-41 MANTENER por el docente del fixture.', 1;
    DELETE FROM #c1d;
    INSERT INTO #c1d EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev2, @codigoDecision = N'PROPONER', @motivo = @mot, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocC;
    IF (SELECT estadoResultado FROM #c1d) <> 1 THROW 58317, 'TEST FAILED: C-DB-41 PROPONER por el docente del fixture.', 1;
    DELETE FROM #c1c;
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT estadoResultado FROM #c1c) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1c) NOT LIKE N'%RCN_012%'
        THROW 58318, 'TEST FAILED: C-DB-40 con una revision PROPUESTA el cierre responde RCN_012.', 1;
    DECLARE @rr TABLE (idCorrelacion UNIQUEIDENTIFIER, u NVARCHAR(4000), t NVARCHAR(4000), estado BIT, idRevision UNIQUEIDENTIFIER, ea NVARCHAR(20), en NVARCHAR(20), cd NVARCHAR(20),
        sc BIT, cm BIT, idGrupo UNIQUEIDENTIFIER, idEg UNIQUEIDENTIFIER, idEst UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER, perfil NVARCHAR(20), pct DECIMAL(5,2), plantilla VARCHAR(60));
    INSERT INTO @rr EXEC dbo.usp_resolver_revision_cancelacion @idRevision = @rev2, @codigoDecision = N'APROBAR', @motivo = @mot, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoordC;
    IF (SELECT estado FROM @rr) <> 1 THROW 58319, 'TEST FAILED: C-DB-41 el coordinador del programa A aprueba la cancelacion.', 1;
    DELETE FROM #c1c;
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT estadoResultado FROM #c1c) <> 1 OR (SELECT COUNT(*) FROM #c1c) <> 1
        THROW 58320, 'TEST FAILED: C-DB-41 resueltos los casos, el cierre termina (GEN_004).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @egAbs2 AND estado = @estCanc) OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @egAbs1 AND estado = @estFin)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @egPres AND estado = @estFin)
       OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupoC AND cantidadEstudiantesFinalizaron = 2 AND cantidadEstudiantesCancelaronAutomaticamente = 1)
        THROW 58321, 'TEST FAILED: C-DB-41 mantenido y presente en F, aprobado en CI, contadores 2/1.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND result = N'SUCCESS' AND JSON_VALUE(metadata, '$.motorHabilitado') = N'true'
                   AND JSON_VALUE(metadata, '$.canceladosPorInasistencia') = N'1')
        THROW 58322, 'TEST FAILED: C-DB-41 la auditoria del cierre debe registrar motorHabilitado y canceladosPorInasistencia.', 1;
    IF @@TRANCOUNT <> 1 THROW 58323, 'TEST FAILED: C-DB-41 el cierre destruyo la transaccion del llamador.', 1;

    PRINT 'TEST_PASS:CULM001_C_CIERRE_BLOQUEO_Y_RESOLUCION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58399, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58398, 'TEST FAILED: C cierre masivo dejo una transaccion abierta.', 1;
GO

-- C-DB-43 / C-DB-44 / C-DB-47: motor apagado y umbral invalido no bloquean y quedan auditados; error forzado -> una fila
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_cierre_fixture.sql
    IF OBJECT_ID(N'tempdb..#c1c') IS NOT NULL DROP TABLE #c1c;
    CREATE TABLE #c1c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    IF OBJECT_ID(N'tempdb..#c1ev') IS NOT NULL DROP TABLE #c1ev;
    CREATE TABLE #c1ev (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        alertasCreadas INT, alertasSuperadas INT, alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));

    -- error forzado (usuario sin perfil ADMINISTRADOR): una sola fila y estado 0
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocC;
    IF (SELECT COUNT(*) FROM #c1c) <> 1 OR (SELECT estadoResultado FROM #c1c) <> 0 THROW 58330, 'TEST FAILED: C-DB-47 el error forzado devuelve una fila con estado 0.', 1;
    DELETE FROM #c1c;

    -- C-DB-43: una revision pendiente (motor sobre una matricula) y una perdida sin revision, con el motor apagado
    INSERT INTO #c1ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @grupoC, @idCorrelacion = @corr, @idEstudianteGrupo = @egAbs1;
    UPDATE dbo.CatalogoParametro SET valor = N'false' WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT COUNT(*) FROM #c1c) <> 1 OR (SELECT estadoResultado FROM #c1c) <> 1
       OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupoC AND estado = @estFin) <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND JSON_VALUE(metadata, '$.motorHabilitado') = N'false'
                      AND JSON_VALUE(metadata, '$.perdidasSinRevision') = N'1' AND JSON_VALUE(metadata, '$.revisionesPendientes') = N'1')
        THROW 58331, 'TEST FAILED: C-DB-43 con el motor apagado no bloquea: todas pasan a F y se audita motorHabilitado=false, 1 sin revision, 1 pendiente.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'true' WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';

    -- C-DB-44: umbral de perdida invalido
    UPDATE dbo.EstudianteGrupo SET estado = @estAct WHERE grupo = @grupoC;
    UPDATE dbo.CatalogoParametro SET valor = N'x' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #c1c;
    INSERT INTO #c1c EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_C', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT estadoResultado FROM #c1c) <> 1 OR (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupoC AND estado = @estFin) <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND JSON_VALUE(metadata, '$.umbralesValidos') = N'false')
        THROW 58332, 'TEST FAILED: C-DB-44 con umbral invalido no bloquea, A -> F y umbralesValidos=false.', 1;
    UPDATE dbo.CatalogoParametro SET valor = N'20' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';

    PRINT 'TEST_PASS:CULM001_C_CIERRE_MOTOR_APAGADO_Y_UNA_FILA';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg2 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58397, @msg2, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58396, 'TEST FAILED: C cierre masivo (motor apagado) dejo una transaccion abierta.', 1;
GO
