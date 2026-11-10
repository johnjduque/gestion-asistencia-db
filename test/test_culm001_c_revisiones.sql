USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- CULM-001 C.1 (CONTRACT §2.13.1 C-DB-20..34): revision de cancelacion: una por perdida, decision del docente, resolucion del
-- coordinador por programa del estudiante (grupo mixto), proponente excluido sin coordinador -> RCN_013 (DEC-065: sin escalamiento al decano), listados del decano (solo lectura) y del docente, destinatarios,
-- resumen del docente y reasignacion por el job. Transaccion revertida; deja @@TRANCOUNT = 0.
PRINT 'TEST START: test_culm001_c_revisiones';
IF OBJECT_ID(N'tempdb..#c1_faltas') IS NOT NULL DROP PROCEDURE #c1_faltas;
GO
CREATE PROCEDURE #c1_faltas @eg UNIQUEIDENTIFIER, @k INT
AS
BEGIN
    UPDATE da SET asistio = IIF(s.n <= @k, 0, 1), razonCausa = (SELECT id FROM dbo.RazonCausa WHERE codigo = IIF(s.n <= @k, N'SJC', N'AN'))
    FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia INNER JOIN #c1s s ON s.idSesion = a.sesion
    WHERE a.estudianteGrupo = @eg;
END;
GO
IF OBJECT_ID(N'tempdb..#c1_eval') IS NOT NULL DROP PROCEDURE #c1_eval;
GO
CREATE PROCEDURE #c1_eval @grupo UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER
AS
BEGIN
    DELETE FROM #c1ev;
    INSERT INTO #c1ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @grupo, @idCorrelacion = @corr, @idEstudianteGrupo = NULL;
END;
GO
IF OBJECT_ID(N'tempdb..#c1_decidir') IS NOT NULL DROP PROCEDURE #c1_decidir;
GO
CREATE PROCEDURE #c1_decidir @rev UNIQUEIDENTIFIER, @dec NVARCHAR(20), @motivo NVARCHAR(MAX), @user UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER
AS
BEGIN
    DELETE FROM #c1d;
    INSERT INTO #c1d EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev, @codigoDecision = @dec, @motivo = @motivo, @idCorrelacion = @corr, @idUsuarioEjecutor = @user;
END;
GO
IF OBJECT_ID(N'tempdb..#c1_resolver') IS NOT NULL DROP PROCEDURE #c1_resolver;
GO
CREATE PROCEDURE #c1_resolver @rev UNIQUEIDENTIFIER, @dec NVARCHAR(20), @motivo NVARCHAR(MAX), @user UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER
AS
BEGIN
    DELETE FROM #c1r;
    INSERT INTO #c1r EXEC dbo.usp_resolver_revision_cancelacion @idRevision = @rev, @codigoDecision = @dec, @motivo = @motivo, @idCorrelacion = @corr, @idUsuarioEjecutor = @user;
END;
GO
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_fixture.sql
    IF OBJECT_ID(N'tempdb..#c1ev') IS NOT NULL DROP TABLE #c1ev;
    CREATE TABLE #c1ev (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        alertasCreadas INT, alertasSuperadas INT, alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));
    IF OBJECT_ID(N'tempdb..#c1d') IS NOT NULL DROP TABLE #c1d;
    CREATE TABLE #c1d (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        idRevision UNIQUEIDENTIFIER, codigoEstadoAnterior NVARCHAR(20), codigoEstadoNuevo NVARCHAR(20), codigoDecision NVARCHAR(20), sinCambios BIT,
        idGrupo UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, porcentajeActual DECIMAL(5,2),
        tipoPlantillaNotificacion VARCHAR(60), codigoPerfilResolutor NVARCHAR(20), esEscalamiento BIT);
    IF OBJECT_ID(N'tempdb..#c1r') IS NOT NULL DROP TABLE #c1r;
    CREATE TABLE #c1r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        idRevision UNIQUEIDENTIFIER, codigoEstadoAnterior NVARCHAR(20), codigoEstadoNuevo NVARCHAR(20), codigoDecision NVARCHAR(20), sinCambios BIT, cambioMatricula BIT,
        idGrupo UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER,
        codigoPerfilResolucion NVARCHAR(20), porcentajeActual DECIMAL(5,2), tipoPlantillaNotificacion VARCHAR(60));
    DECLARE @mot NVARCHAR(100) = N'Motivo de prueba suficiente';
    DECLARE @revEA UNIQUEIDENTIFIER, @revEB UNIQUEIDENTIFIER, @rev0 UNIQUEIDENTIFIER;

    -- Escenario base: EA, EB y E0 en pérdida (9 faltas = 36 %); una sola revision por matricula tras 3 evaluaciones (C-DB-20)
    EXEC #c1_faltas @egEA, 9; EXEC #c1_faltas @egEB, 9; EXEC #c1_faltas @eg0, 9;
    EXEC #c1_eval @grupoG, @c; EXEC #c1_eval @grupoG, @c; EXEC #c1_eval @grupoG, @c;
    IF (SELECT COUNT(*) FROM dbo.RevisionCancelacion WHERE estudianteGrupo IN (@egEA, @egEB, @eg0)) <> 3
       OR (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial h INNER JOIN dbo.RevisionCancelacion r ON r.id = h.revision WHERE r.estudianteGrupo IN (@egEA, @egEB, @eg0) AND h.codigoEvento = N'CREAR') <> 3
        THROW 58110, 'TEST FAILED: C-DB-20 debe existir 1 revision y 1 historial CREAR por matricula tras 3 evaluaciones.', 1;
    SELECT @revEA = id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egEA;
    SELECT @revEB = id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egEB;
    SELECT @rev0  = id FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @eg0;

    -- C-DB-22: motivo y decision
    EXEC #c1_decidir @revEA, N'MANTENER', N'', @uT, @c;
    IF (SELECT estadoResultado FROM #c1d) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_003%' THROW 58120, 'TEST FAILED: C-DB-22 motivo vacio -> RCN_003.', 1;
    EXEC #c1_decidir @revEA, N'MANTENER', N'123456789', @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_003%' THROW 58121, 'TEST FAILED: C-DB-22 motivo de 9 caracteres -> RCN_003.', 1;
    DECLARE @mot501 NVARCHAR(600) = REPLICATE(N'x', 501);
    EXEC #c1_decidir @revEA, N'MANTENER', @mot501, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_003%' THROW 58122, 'TEST FAILED: C-DB-22 motivo de 501 caracteres -> RCN_003.', 1;
    EXEC #c1_decidir @revEA, N'APROBAR', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_002%' THROW 58123, 'TEST FAILED: C-DB-22 APROBAR por el docente -> RCN_002.', 1;

    -- C-DB-23: otro docente y revision inexistente -> RCN_001
    DECLARE @uT2 UNIQUEIDENTIFIER = NEWID(), @docT2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uT2, @tipoCC, 1950000011, N'CULMC', N'', N'DocT2', N'', N'culmc.doct2@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@docT2, @uT2);
    EXEC #c1_decidir @revEA, N'MANTENER', @mot, @uT2, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_001%' THROW 58124, 'TEST FAILED: C-DB-23 docente ajeno -> RCN_001.', 1;
    EXEC #c1_decidir '00000000-0000-0000-0000-0000000000AB', N'MANTENER', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_001%' THROW 58125, 'TEST FAILED: C-DB-23 revision inexistente -> RCN_001.', 1;

    -- C-DB-21 / C-DB-24: MANTENER (RCN_007), idempotente (RCN_011 sin historial nuevo), sin nueva alerta aunque suba, luego PROPONER
    EXEC #c1_decidir @revEA, N'MANTENER', @mot, @uT, @c;
    IF (SELECT estadoResultado FROM #c1d) <> 1 OR (SELECT codigoEstadoNuevo FROM #c1d) <> N'MANTENIDA' OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_007%'
        THROW 58126, 'TEST FAILED: C-DB-21 MANTENER -> MANTENIDA (RCN_007).', 1;
    DECLARE @hist INT = (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEA);
    EXEC #c1_decidir @revEA, N'MANTENER', @mot, @uT, @c;
    IF (SELECT sinCambios FROM #c1d) <> 1 OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_011%' OR (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEA) <> @hist
        THROW 58127, 'TEST FAILED: C-DB-24 MANTENIDA + MANTENER -> RCN_011 sin historial nuevo.', 1;
    EXEC #c1_faltas @egEA, 12;
    EXEC #c1_eval @grupoG, @c;
    IF (SELECT alertasCreadas FROM #c1ev) <> 0 OR (SELECT revisionesCreadas FROM #c1ev) <> 0 OR (SELECT COUNT(*) FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egEA) <> 1
        THROW 58128, 'TEST FAILED: C-DB-21 tras MANTENER, subir el porcentaje no crea alerta ni revision nuevas.', 1;
    EXEC #c1_decidir @revEA, N'PROPONER', @mot, @uT, @c;
    IF (SELECT estadoResultado FROM #c1d) <> 1 OR (SELECT codigoEstadoNuevo FROM #c1d) <> N'PROPUESTA' OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_008%'
       OR (SELECT codigoPerfilResolutor FROM #c1d) <> N'COORDINADOR' OR (SELECT esEscalamiento FROM #c1d) <> 0
        THROW 58129, 'TEST FAILED: C-DB-21 PROPONER -> PROPUESTA a COORDINADOR (RCN_008).', 1;
    EXEC #c1_decidir @revEA, N'MANTENER', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_004%' THROW 58130, 'TEST FAILED: C-DB-24 PROPUESTA + MANTENER -> RCN_004.', 1;
    EXEC #c1_decidir @revEA, N'PROPONER', @mot, @uT, @c;
    IF (SELECT sinCambios FROM #c1d) <> 1 OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_011%' THROW 58131, 'TEST FAILED: C-DB-24 PROPUESTA + PROPONER -> RCN_011.', 1;

    -- C-DB-28: grupo mixto. CA ve a EA y no a EB; CB al reves; CA resolviendo EB -> RCN_001; E0 no tiene resolutor
    EXEC #c1_decidir @revEB, N'PROPONER', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_008%' THROW 58140, 'TEST FAILED: C-DB-28 PROPONER sobre EB.', 1;
    IF OBJECT_ID(N'tempdb..#c1l') IS NOT NULL DROP TABLE #c1l;
    CREATE TABLE #c1l (id UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idUsuarioEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400),
        idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        idDocenteTitular UNIQUEIDENTIFIER, idUsuarioDocenteTitular UNIQUEIDENTIFIER, nombreCompletoDocente NVARCHAR(400), codigoEstadoMatricula NVARCHAR(50),
        idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), nombreEstado NVARCHAR(60), ordenEstado TINYINT, requiereAccionDocente BIT, requiereAccionResolutor BIT,
        conservaMatricula BIT, cancelaMatricula BIT, esFinal BIT, porcentajeCreacion DECIMAL(5,2), horasFaltaCreacion DECIMAL(12,6), horasDictadasCreacion DECIMAL(12,6),
        fechaCreacionUtc DATETIME2(3), codigoDecisionDocente NVARCHAR(20), motivoDocente NVARCHAR(1000), idUsuarioDecisionDocente UNIQUEIDENTIFIER, porcentajeDecisionDocente DECIMAL(5,2),
        fechaDecisionDocenteUtc DATETIME2(3), codigoPerfilResolutorActual NVARCHAR(20), fechaEscalamientoUtc DATETIME2(3), codigoDecisionResolucion NVARCHAR(20), motivoResolucion NVARCHAR(1000),
        idUsuarioResolucion UNIQUEIDENTIFIER, nombreCompletoResolucion NVARCHAR(400), codigoPerfilResolucion NVARCHAR(20), idProgramaResolucion UNIQUEIDENTIFIER,
        nombreProgramaResolucion NVARCHAR(100), porcentajeResolucion DECIMAL(5,2), fechaResolucionUtc DATETIME2(3), fechaActualizacionUtc DATETIME2(3),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), porcentajeActual DECIMAL(5,2), horasFaltaActual DECIMAL(12,6), horasDictadasActual DECIMAL(12,6),
        umbralPerdida DECIMAL(5,2), esResolutorActual BIT, accionesPermitidas NVARCHAR(200), totalRegistros INT);
    INSERT INTO #c1l EXEC dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = NULL, @idGrupo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #c1l WHERE id = @revEA AND esResolutorActual = 1 AND accionesPermitidas LIKE N'%APROBAR%') OR EXISTS (SELECT 1 FROM #c1l WHERE id IN (@revEB, @rev0))
        THROW 58141, 'TEST FAILED: C-DB-28 CA debe ver a EA (resolutor) y no a EB ni a E0.', 1;
    DELETE FROM #c1l;
    INSERT INTO #c1l EXEC dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = NULL, @idGrupo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #c1l WHERE id = @revEB) OR EXISTS (SELECT 1 FROM #c1l WHERE id IN (@revEA, @rev0))
        THROW 58142, 'TEST FAILED: C-DB-28 CB debe ver a EB y no a EA ni a E0.', 1;
    EXEC #c1_resolver @revEB, N'APROBAR', @mot, @uCA, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_001%' THROW 58144, 'TEST FAILED: C-DB-28 CA resolviendo la de EB -> RCN_001.', 1;
    EXEC #c1_decidir @rev0, N'PROPONER', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_013%' THROW 58145, 'TEST FAILED: C-DB-28 E0 sin programa en el grupo: PROPONER -> RCN_013.', 1;
    EXEC #c1_resolver @revEA, N'APROBAR', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_014%' THROW 58146, 'TEST FAILED: C-DB-29 el proponente no resuelve su propuesta (RCN_014).', 1;
    EXEC #c1_resolver @revEA, N'APROBAR', @mot, @uAdm, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_001%' THROW 58147, 'TEST FAILED: C-DB-28 el administrador no resuelve (RCN_001).', 1;

    -- C-DB-30: estudiante en PA y PB del mismo coordinador -> 1 fila por revision
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @eA, @progB);
    DELETE FROM #c1l;
    INSERT INTO #c1l EXEC dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = NULL, @idGrupo = NULL;
    IF (SELECT COUNT(*) FROM #c1l) <> (SELECT COUNT(DISTINCT id) FROM #c1l) THROW 58150, 'TEST FAILED: C-DB-30 una fila por revision.', 1;
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @eA AND programa = @progB;

    -- C-DB-31: destinatarios de la revision de EA (estudiante, docente, resolutores sin el proponente); ejecutor ajeno -> RCN_001
    IF OBJECT_ID(N'tempdb..#c1dest') IS NOT NULL DROP TABLE #c1dest;
    CREATE TABLE #c1dest (rolDestinatario NVARCHAR(20), codigoPerfil NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(100),
        idPrograma UNIQUEIDENTIFIER, esEscalamiento BIT, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), nombreAsignatura NVARCHAR(100),
        nombreCompletoEstudiante NVARCHAR(400), nombreCompletoDocente NVARCHAR(400), codigoEstado NVARCHAR(20), porcentajeActual DECIMAL(5,2), umbralPerdida DECIMAL(5,2),
        motivoDocente NVARCHAR(1000), motivoResolucion NVARCHAR(1000), nombreCompletoResolucion NVARCHAR(400));
    INSERT INTO #c1dest EXEC dbo.usp_consultar_destinatarios_revision_cancelacion @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idRevision = @revEA;
    IF (SELECT COUNT(*) FROM #c1dest WHERE rolDestinatario = N'ESTUDIANTE') <> 1 OR (SELECT COUNT(*) FROM #c1dest WHERE rolDestinatario = N'DOCENTE') <> 1
       OR NOT EXISTS (SELECT 1 FROM #c1dest WHERE rolDestinatario = N'RESOLUTOR' AND idUsuario = @uCA) OR EXISTS (SELECT 1 FROM #c1dest WHERE rolDestinatario = N'RESOLUTOR' AND idUsuario = @uT)
        THROW 58151, 'TEST FAILED: C-DB-31 destinatarios (1 estudiante, 1 docente, resolutores sin el proponente).', 1;

    -- C-DB-26: aprobar => CI y fuera del registro (CA aprueba la de EA)
    EXEC #c1_resolver @revEA, N'APROBAR', @mot, @uCA, @c;
    IF (SELECT estadoResultado FROM #c1r) <> 1 OR (SELECT codigoEstadoNuevo FROM #c1r) <> N'APROBADA' OR (SELECT cambioMatricula FROM #c1r) <> 1 OR (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_009%'
        THROW 58160, 'TEST FAILED: C-DB-26 CA aprueba -> APROBADA (RCN_009).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @egEA AND estado = @estCI)
       OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE id = @revEA AND estadoMatriculaAnterior = @estA AND codigoPerfilResolucion = N'COORDINADOR' AND usuarioResolucion = @uCA)
        THROW 58161, 'TEST FAILED: C-DB-26 la matricula debe quedar en CI y la revision registrar el estado anterior y al resolutor.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_faltantes_toma WHERE idEstudianteGrupo = @egEA)
        THROW 58162, 'TEST FAILED: C-DB-26 EA no debe aparecer en uv_faltantes_toma tras la cancelacion.', 1;
    EXEC #c1_eval @grupoG, @c;
    IF EXISTS (SELECT 1 FROM OPENJSON((SELECT novedadesJSON FROM #c1ev)) WITH (idEstudianteGrupo UNIQUEIDENTIFIER '$.idEstudianteGrupo') WHERE idEstudianteGrupo = @egEA)
        THROW 58163, 'TEST FAILED: C-DB-26 la matricula cancelada ya no se evalua.', 1;
    EXEC #c1_resolver @revEA, N'APROBAR', @mot, @uCA, @c;
    IF (SELECT sinCambios FROM #c1r) <> 1 OR (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_011%' THROW 58164, 'TEST FAILED: C-DB-46 segundo APROBAR -> RCN_011.', 1;
    EXEC #c1_resolver @revEA, N'RECHAZAR', @mot, @uCA, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_004%' THROW 58165, 'TEST FAILED: C-DB-46 RECHAZAR tras APROBAR -> RCN_004.', 1;

    -- C-DB-27: rechazar => sigue activo; el docente puede volver a proponer y se limpian las columnas de resolucion
    EXEC #c1_resolver @revEB, N'RECHAZAR', @mot, @uCB, @c;
    IF (SELECT codigoEstadoNuevo FROM #c1r) <> N'RECHAZADA' OR (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_010%' OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @egEB AND estado = @estA)
        THROW 58170, 'TEST FAILED: C-DB-27 CB rechaza -> RECHAZADA y la matricula sigue A.', 1;
    EXEC #c1_decidir @revEB, N'PROPONER', @mot, @uT, @c;
    IF (SELECT codigoEstadoNuevo FROM #c1d) <> N'PROPUESTA' OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE id = @revEB AND codigoDecisionResolucion IS NULL AND usuarioResolucion IS NULL AND fechaResolucionUtc IS NULL)
       OR (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEB) <> 4
        THROW 58171, 'TEST FAILED: C-DB-27 re-proponer limpia la resolucion y deja 4 filas de historial (CREAR, PROPONER, RECHAZAR, PROPONER).', 1;

    -- C-DB-25: umbral. Revision nueva de E0 con porcentaje 16 %: PROPONER -> RCN_006 y MANTENER permitido
    EXEC #c1_faltas @eg0, 4;
    EXEC #c1_decidir @rev0, N'PROPONER', @mot, @uT, @c;
    IF (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_006%' THROW 58180, 'TEST FAILED: C-DB-25 PROPONER bajo el umbral -> RCN_006.', 1;
    EXEC #c1_decidir @rev0, N'MANTENER', @mot, @uT, @c;
    IF (SELECT codigoEstadoNuevo FROM #c1d) <> N'MANTENIDA' THROW 58181, 'TEST FAILED: C-DB-25 MANTENER bajo el umbral es valido.', 1;

    -- C-DB-29 (DEC-065 1): el docente es el unico coordinador del programa A => no hay resolutor: RCN_013 y nada se escala al decano
    DECLARE @coordT UNIQUEIDENTIFIER = NEWID(), @coordA UNIQUEIDENTIFIER = (SELECT coordinador FROM dbo.Programa WHERE id = @progA);
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordT, @uT, 1, @fac);
    UPDATE dbo.Programa SET coordinador = @coordT WHERE id = @progA;
    UPDATE dbo.RevisionCancelacion SET estado = (SELECT id FROM dbo.EstadoRevisionCancelacion WHERE codigo = N'PENDIENTE_DOCENTE'), codigoDecisionDocente = NULL, usuarioDecisionDocente = NULL,
        codigoPerfilResolutorActual = NULL, huellaResolutoresActual = NULL, fechaEscalamientoUtc = NULL, codigoDecisionResolucion = NULL, usuarioResolucion = NULL, codigoPerfilResolucion = NULL, programaResolucion = NULL, fechaResolucionUtc = NULL, estadoMatriculaAnterior = NULL
        WHERE id = @revEA;
    UPDATE dbo.EstudianteGrupo SET estado = @estA WHERE id = @egEA;
    EXEC #c1_faltas @egEA, 12;
    DECLARE @histEA INT = (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEA);
    EXEC #c1_decidir @revEA, N'PROPONER', @mot, @uT, @c;
    IF (SELECT estadoResultado FROM #c1d) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1d) NOT LIKE N'%RCN_013%'
       OR (SELECT COUNT(*) FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEA) <> @histEA
       OR EXISTS (SELECT 1 FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEA AND codigoEvento = N'ESCALAR')
       OR EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'ESCALAR_REVISION_CANCELACION')
       OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
                      WHERE r.id = @revEA AND es.codigo = N'PENDIENTE_DOCENTE' AND r.codigoPerfilResolutorActual IS NULL AND r.fechaEscalamientoUtc IS NULL)
        THROW 58190, 'TEST FAILED: C-DB-29 (DEC-065) sin otro coordinador: RCN_013, sin escalar al decano ni cambiar el estado.', 1;
    IF (SELECT mensajeUsuarioResultado FROM #c1d) NOT LIKE N'%solicite su asignación al decano%'
        THROW 58191, 'TEST FAILED: C-DB-29 (DEC-065) el mensaje RCN_013 debe pedir asignar un coordinador al decano.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ufn_revision_cancelacion_resolutores(@egEA, @uT) WHERE codigoPerfil <> N'COORDINADOR' OR esEscalamiento <> 0)
        THROW 58192, 'TEST FAILED: C-DB-29 (DEC-065) la funcion de resolutores nunca devuelve al decano ni esEscalamiento = 1.', 1;
    UPDATE dbo.Programa SET coordinador = @coordA WHERE id = @progA;

    -- C-DB-33 (DEC-065 1 y 4): el decano consulta TODAS las revisiones de su facultad (solo lectura) y no puede resolver (RCN_016)
    IF OBJECT_ID(N'tempdb..#c1ld') IS NOT NULL DROP TABLE #c1ld;
    CREATE TABLE #c1ld (id UNIQUEIDENTIFIER, idEstudianteGrupo UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idUsuarioEstudiante UNIQUEIDENTIFIER, nombreCompletoEstudiante NVARCHAR(400),
        idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        idDocenteTitular UNIQUEIDENTIFIER, idUsuarioDocenteTitular UNIQUEIDENTIFIER, nombreCompletoDocente NVARCHAR(400), codigoEstadoMatricula NVARCHAR(50),
        idEstado UNIQUEIDENTIFIER, codigoEstado NVARCHAR(20), nombreEstado NVARCHAR(60), ordenEstado TINYINT, requiereAccionDocente BIT, requiereAccionResolutor BIT,
        conservaMatricula BIT, cancelaMatricula BIT, esFinal BIT, porcentajeCreacion DECIMAL(5,2), horasFaltaCreacion DECIMAL(12,6), horasDictadasCreacion DECIMAL(12,6),
        fechaCreacionUtc DATETIME2(3), codigoDecisionDocente NVARCHAR(20), motivoDocente NVARCHAR(1000), idUsuarioDecisionDocente UNIQUEIDENTIFIER, porcentajeDecisionDocente DECIMAL(5,2),
        fechaDecisionDocenteUtc DATETIME2(3), codigoPerfilResolutorActual NVARCHAR(20), fechaEscalamientoUtc DATETIME2(3), codigoDecisionResolucion NVARCHAR(20), motivoResolucion NVARCHAR(1000),
        idUsuarioResolucion UNIQUEIDENTIFIER, nombreCompletoResolucion NVARCHAR(400), codigoPerfilResolucion NVARCHAR(20), idProgramaResolucion UNIQUEIDENTIFIER,
        nombreProgramaResolucion NVARCHAR(100), porcentajeResolucion DECIMAL(5,2), fechaResolucionUtc DATETIME2(3), fechaActualizacionUtc DATETIME2(3),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), porcentajeActual DECIMAL(5,2), horasFaltaActual DECIMAL(12,6), horasDictadasActual DECIMAL(12,6),
        umbralPerdida DECIMAL(5,2), esResolutorActual BIT, accionesPermitidas NVARCHAR(200), totalRegistros INT);
    INSERT INTO #c1ld EXEC dbo.usp_consultar_revisiones_cancelacion_decano_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = NULL;
    IF NOT EXISTS (SELECT 1 FROM #c1ld WHERE id = @revEA) OR NOT EXISTS (SELECT 1 FROM #c1ld WHERE id = @revEB) OR NOT EXISTS (SELECT 1 FROM #c1ld WHERE id = @rev0)
       OR (SELECT COUNT(*) FROM #c1ld) <> (SELECT COUNT(*) FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
                                           WHERE EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(eg.grupo) pg INNER JOIN dbo.Programa p ON p.id = pg.idPrograma WHERE p.facultad = @fac))
       OR EXISTS (SELECT 1 FROM #c1ld WHERE esResolutorActual <> 0 OR accionesPermitidas <> N'' OR idPrograma NOT IN (SELECT id FROM dbo.Programa WHERE facultad = @fac))
        THROW 58200, 'TEST FAILED: C-DB-33 (DEC-065) el decano ve todas las revisiones de su facultad (cualquier estado) sin acciones.', 1;
    DELETE FROM #c1ld;
    INSERT INTO #c1ld EXEC dbo.usp_consultar_revisiones_cancelacion_decano_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 1, @codigoEstado = NULL, @idPrograma = NULL;
    IF NOT EXISTS (SELECT 1 FROM #c1ld WHERE id = @revEB) OR EXISTS (SELECT 1 FROM #c1ld WHERE requiereAccionResolutor = 0)
        THROW 58203, 'TEST FAILED: C-DB-33 (DEC-065) soloPendientes del decano deja solo las que esperan al coordinador.', 1;
    DELETE FROM #c1ld;
    INSERT INTO #c1ld EXEC dbo.usp_consultar_revisiones_cancelacion_decano_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @soloPendientes = 0, @codigoEstado = N'PROPUESTA', @idPrograma = @progB;
    IF NOT EXISTS (SELECT 1 FROM #c1ld WHERE id = @revEB) OR EXISTS (SELECT 1 FROM #c1ld WHERE codigoEstado <> N'PROPUESTA' OR idPrograma <> @progB)
        THROW 58204, 'TEST FAILED: C-DB-33 (DEC-065) filtros estado y programa del decano.', 1;
    DECLARE @progAjeno UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Programa WHERE facultad <> @fac);
    DECLARE @estRevEB UNIQUEIDENTIFIER = (SELECT estado FROM dbo.RevisionCancelacion WHERE id = @revEB);
    EXEC #c1_resolver @revEB, N'APROBAR', @mot, @uDec, @c;
    IF (SELECT estadoResultado FROM #c1r) <> 0 OR (SELECT mensajeTecnicoResultado FROM #c1r) NOT LIKE N'%RCN_016%'
       OR (SELECT mensajeUsuarioResultado FROM #c1r) NOT LIKE N'%corresponde al coordinador%'
       OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE id = @revEB AND estado = @estRevEB AND usuarioResolucion IS NULL)
       OR EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND path LIKE N'/api/v1/decano/%')
        THROW 58202, 'TEST FAILED: C-DB-33 (DEC-065) el decano que resuelve recibe RCN_016 sin cambios de estado ni auditoria /decano.', 1;

    -- C-DB-34 (DEC-065 1 y 3): reasignacion por el job. Propuesta de EB con CB; CB se desactiva: sin resolutor (nunca decano); reactivado: REASIGNAR
    IF OBJECT_ID(N'tempdb..#c1j') IS NOT NULL DROP TABLE #c1j;
    CREATE TABLE #c1j (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        revisionesReasignadas INT, revisionesEscaladas INT, revisionesSinResolutor INT, novedadesJSON NVARCHAR(MAX));
    UPDATE dbo.Coordinador SET estado = 0 WHERE id = @coordB;
    INSERT INTO #c1j EXEC dbo.usp_actualizar_resolutores_revisiones_cancelacion @idCorrelacion = @c, @tamanoLote = 500;
    IF (SELECT estadoResultado FROM #c1j) <> 1 OR (SELECT revisionesEscaladas FROM #c1j) <> 0 OR (SELECT revisionesSinResolutor FROM #c1j) < 1
       OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE id = @revEB AND codigoPerfilResolutorActual IS NULL AND fechaEscalamientoUtc IS NULL)
       OR EXISTS (SELECT 1 FROM dbo.RevisionCancelacionHistorial WHERE codigoEvento = N'ESCALAR' OR codigoPerfilResolutor = N'DECANO')
       OR EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'ESCALAR_REVISION_CANCELACION')
       OR NOT EXISTS (SELECT 1 FROM OPENJSON((SELECT novedadesJSON FROM #c1j)) WITH (idRevision UNIQUEIDENTIFIER '$.idRevision') WHERE idRevision = @revEB)
        THROW 58210, 'TEST FAILED: C-DB-34 (DEC-065) al desactivar al coordinador la propuesta queda sin resolutor y nunca se escala al decano.', 1;
    DELETE FROM #c1j;
    INSERT INTO #c1j EXEC dbo.usp_actualizar_resolutores_revisiones_cancelacion @idCorrelacion = @c, @tamanoLote = 500;
    IF NOT EXISTS (SELECT 1 FROM #c1j WHERE estadoResultado = 1 AND revisionesEscaladas = 0 AND revisionesReasignadas = 0 AND revisionesSinResolutor = 0)
        THROW 58211, 'TEST FAILED: C-DB-34 la huella sin cambios no genera novedades (la ausencia de resolutor se registra una sola vez).', 1;
    UPDATE dbo.Coordinador SET estado = 1 WHERE id = @coordB;
    DELETE FROM #c1j;
    INSERT INTO #c1j EXEC dbo.usp_actualizar_resolutores_revisiones_cancelacion @idCorrelacion = @c, @tamanoLote = 500;
    IF (SELECT revisionesReasignadas FROM #c1j) < 1 OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion WHERE id = @revEB AND codigoPerfilResolutorActual = N'COORDINADOR')
       OR NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacionHistorial WHERE revision = @revEB AND codigoEvento = N'REASIGNAR')
        THROW 58212, 'TEST FAILED: C-DB-34 al volver el coordinador la revision se reasigna (REASIGNAR).', 1;
    UPDATE dbo.Decano SET estado = 0 WHERE usuario = @uDec;
    UPDATE dbo.Coordinador SET estado = 0 WHERE id = @coordB;
    DELETE FROM #c1j;
    INSERT INTO #c1j EXEC dbo.usp_actualizar_resolutores_revisiones_cancelacion @idCorrelacion = @c, @tamanoLote = 500;
    IF (SELECT revisionesSinResolutor FROM #c1j) < 1 OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @c AND action = 'REVISION_CANCELACION_SIN_RESOLUTOR')
        THROW 58213, 'TEST FAILED: C-DB-34 sin coordinador activo: REVISION_CANCELACION_SIN_RESOLUTOR.', 1;
    UPDATE dbo.Coordinador SET estado = 1 WHERE id = @coordB;
    UPDATE dbo.Decano SET estado = 1 WHERE usuario = @uDec;

    -- C-DB-35 (DEC-065 6): consulta de revisiones del docente titular (todas las suyas, ninguna ajena, mismas columnas que el coordinador)
    DECLARE @colsDoc NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
        FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = ''00000000-0000-0000-0000-000000000001'', @idCorrelacion = ''00000000-0000-0000-0000-000000000001''', NULL, 0));
    DECLARE @colsCoo NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
        FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado @idUsuarioEjecutor = ''00000000-0000-0000-0000-000000000001'', @idCorrelacion = ''00000000-0000-0000-0000-000000000001''', NULL, 0));
    IF @colsDoc IS NULL OR @colsDoc <> @colsCoo
        THROW 58230, 'TEST FAILED: C-DB-35 el SP del docente debe devolver las mismas columnas que el del coordinador.', 1;
    IF OBJECT_ID(N'tempdb..#c1lt') IS NOT NULL DROP TABLE #c1lt;
    SELECT * INTO #c1lt FROM #c1ld WHERE 1 = 0;
    INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c, @soloPendientes = 0, @idGrupo = NULL, @estado = NULL,
        @numeroPagina = 1, @tamanoPagina = 50;
    IF (SELECT COUNT(*) FROM #c1lt) <> (SELECT COUNT(*) FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo WHERE eg.grupo = @grupoG)
       OR NOT EXISTS (SELECT 1 FROM #c1lt WHERE id = @revEA) OR NOT EXISTS (SELECT 1 FROM #c1lt WHERE id = @revEB) OR NOT EXISTS (SELECT 1 FROM #c1lt WHERE id = @rev0)
       OR EXISTS (SELECT 1 FROM #c1lt WHERE idGrupo <> @grupoG OR idUsuarioDocenteTitular <> @uT OR esResolutorActual <> 0 OR accionesPermitidas <> N'')
       OR (SELECT MIN(totalRegistros) FROM #c1lt) <> (SELECT COUNT(*) FROM #c1lt) OR (SELECT MAX(totalRegistros) FROM #c1lt) <> (SELECT COUNT(*) FROM #c1lt)
        THROW 58231, 'TEST FAILED: C-DB-35 el docente titular ve todas las revisiones de su grupo con totalRegistros.', 1;
    DELETE FROM #c1lt;
    INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c, @soloPendientes = 1, @idGrupo = @grupoG, @estado = NULL,
        @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #c1lt WHERE requiereAccionDocente = 0 OR codigoEstado <> N'PENDIENTE_DOCENTE')
       OR (SELECT COUNT(*) FROM #c1lt) <> (SELECT COUNT(*) FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
                                           INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo WHERE eg.grupo = @grupoG AND es.requiereAccionDocente = 1)
        THROW 58233, 'TEST FAILED: C-DB-35 soloPendientes del docente deja solo PENDIENTE_DOCENTE.', 1;
    DELETE FROM #c1lt;
    INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c, @soloPendientes = 0, @idGrupo = NULL, @estado = N'propuesta',
        @numeroPagina = 1, @tamanoPagina = 50;
    IF NOT EXISTS (SELECT 1 FROM #c1lt WHERE id = @revEB) OR EXISTS (SELECT 1 FROM #c1lt WHERE codigoEstado <> N'PROPUESTA')
        THROW 58234, 'TEST FAILED: C-DB-35 filtro de estado del docente.', 1;
    DELETE FROM #c1lt;
    INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c, @soloPendientes = 0, @idGrupo = NULL, @estado = NULL,
        @numeroPagina = 2, @tamanoPagina = 1;
    IF (SELECT COUNT(*) FROM #c1lt) <> 1 OR (SELECT MAX(totalRegistros) FROM #c1lt) < 3
        THROW 58235, 'TEST FAILED: C-DB-35 paginacion del docente: la pagina 2 de tamano 1 trae una fila y totalRegistros el total.', 1;
    DELETE FROM #c1lt;
    INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT2, @idCorrelacion = @c, @soloPendientes = 0, @idGrupo = NULL, @estado = NULL,
        @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #c1lt)
        THROW 58236, 'TEST FAILED: C-DB-35 un docente sin grupos no ve revisiones ajenas.', 1;

    -- C-DB-32: el resumen del docente conserva sus columnas y agrega las de C al final
    DECLARE @cols NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
        FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado @idUsuarioEjecutor = ''00000000-0000-0000-0000-000000000001'', @idCorrelacion = ''00000000-0000-0000-0000-000000000001'', @idGrupo = ''00000000-0000-0000-0000-000000000001''', NULL, 0));
    IF @cols IS NULL OR @cols NOT LIKE N'idEstudianteGrupo,idEstudiante,idGrupo,idAsignatura,idPeriodoAcademico,codigoEstadoEstudiante,%,nombreCompletoEstudiante,totalRegistros,tieneAdvertenciaVigente,fechaAdvertenciaUtc,tienePerdidaVigente,fechaPerdidaUtc,idRevisionCancelacion,codigoEstadoRevision,nombreEstadoRevision,requiereAccionDocente,codigoPerfilResolutorActual,accionesPermitidasRevision'
        THROW 58220, 'TEST FAILED: C-DB-32 el resumen del docente debe conservar sus columnas y agregar las de C al final.', 1;

    -- Verificaciones de error con THROW 51000 (el SP corre con XACT_ABORT ON: la transaccion de prueba queda sin posibilidad de escribir,
    -- por eso van al final)
    DECLARE @coo3 BIT = 0;
    BEGIN TRY
        INSERT INTO #c1l EXEC dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
            @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = @progB, @idGrupo = NULL;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%COO_003%' SET @coo3 = 1;
    END CATCH
    IF @coo3 = 0 THROW 58143, 'TEST FAILED: C-DB-28 @idPrograma ajeno -> COO_003.', 1;
    DECLARE @sec2doc BIT = 0;
    BEGIN TRY
        INSERT INTO #c1lt EXEC dbo.usp_consultar_revisiones_cancelacion_docente_paginado @idUsuario = @uT2, @idCorrelacion = @c, @soloPendientes = 0, @idGrupo = @grupoG, @estado = NULL,
            @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%SEC_002%' SET @sec2doc = 1;
    END CATCH
    IF @sec2doc = 0 THROW 58237, 'TEST FAILED: C-DB-35 @idGrupo de otro docente -> SEC_002.', 1;
    DECLARE @dest001 BIT = 0;
    BEGIN TRY
        INSERT INTO #c1dest EXEC dbo.usp_consultar_destinatarios_revision_cancelacion @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @idRevision = @revEA;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%RCN_001%' SET @dest001 = 1;
    END CATCH
    IF @dest001 = 0 THROW 58152, 'TEST FAILED: C-DB-31 ejecutor ajeno -> RCN_001.', 1;
    IF @progAjeno IS NOT NULL
    BEGIN
        DECLARE @coo3d BIT = 0;
        BEGIN TRY
            INSERT INTO #c1ld EXEC dbo.usp_consultar_revisiones_cancelacion_decano_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
                @soloPendientes = 0, @codigoEstado = NULL, @idPrograma = @progAjeno;
        END TRY
        BEGIN CATCH
            IF ERROR_MESSAGE() LIKE N'%COO_003%' SET @coo3d = 1;
        END CATCH
        IF @coo3d = 0 THROW 58201, 'TEST FAILED: C-DB-33 programa de otra facultad -> COO_003.', 1;
    END

    PRINT 'TEST_PASS:CULM001_C_REVISIONES';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58199, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58198, 'TEST FAILED: C revisiones dejo una transaccion abierta.', 1;
GO
