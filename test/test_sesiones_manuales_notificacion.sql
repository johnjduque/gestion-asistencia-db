USE [gestionasistenciadb];
GO
-- CULM-001 / DEC-064 / HU047: sesiones creadas manualmente por el docente (procedenciaTemporal NULL de v1 o UTC_V2 de v2; la precarga marca UTC_GENERADOR).
--   SMN-00 objetos y semillas de la migracion 29
--   SMN-01 destinatarios: estudiantes activos del grupo + coordinador(es) activo(s) de los programas del grupo (un coordinador de dos programas, una fila)
--   SMN-02 una sesion no manual (UTC_GENERADOR) no tiene destinatarios
--   SMN-03 solo el docente consulta los destinatarios (un coordinador recibe SEC_001; fuera de la transaccion principal por el THROW)
--   SMN-04 un coordinador inactivo no es destinatario
--   SMN-05 el coordinador cancela una sesion manual de su ambito (tipo manual, motivo del catalogo, auditoria, SES_020)
--   SMN-06 fuera de ambito SEC_002; docente SEC_001; no manual SES_018; motivo fuera de catalogo SES_019; observacion larga SES_021; doble cancelacion SES_011
--   SMN-07 consulta del catalogo de motivos (solo coordinador)
-- Todo dentro de una transaccion revertida; @@TRANCOUNT = 0 al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_sesiones_manuales_notificacion';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @sMan UNIQUEIDENTIFIER = NEWID(), @sGen UNIQUEIDENTIFIER = NEWID(), @sMan2 UNIQUEIDENTIFIER = NEWID(), @sV1 UNIQUEIDENTIFIER = NEWID(), @sOwner UNIQUEIDENTIFIER = NEWID();

    -- SMN-00: objetos y semillas
    IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NULL
       OR OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NULL OR OBJECT_ID(N'dbo.MotivoCancelacionSesion', N'U') IS NULL
        THROW 58001, 'TEST FAILED CULM001_SMN_00: faltan objetos de sesiones manuales (migracion 29).', 1;
    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE activa = 1 AND tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')) <> 2
       OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')) <> 14
        THROW 58002, 'TEST FAILED CULM001_SMN_00: plantillas SESION_MANUAL_CREADA_* o sus 14 marcadores ausentes.', 1;
    IF EXISTS (SELECT 1 FROM (VALUES ('SES_018'), ('SES_019'), ('SES_020'), ('SES_021')) m(codigo)
               WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = m.codigo) OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = m.codigo))
        THROW 58003, 'TEST FAILED CULM001_SMN_00: mensajes SES_018..SES_021 ausentes.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1) < 3
       OR dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA') IS NULL
        THROW 58004, 'TEST FAILED CULM001_SMN_00: el catalogo de motivos o el parametro de observacion no estan sembrados.', 1;
    PRINT 'TEST_PASS:CULM001_SMN_00_OBJETOS_Y_SEMILLAS';

    -- sesiones del grupo mixto G (titular uT): dos manuales (UTC_V2) y una generada (UTC_GENERADOR)
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sMan,  N'SMN manual',   901, N'SMN901', 1, @grupoG, DATEADD(DAY, 3, SYSUTCDATETIME()), DATEADD(MINUTE, 3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sGen,  N'SMN generada', 902, N'SMN902', 1, @grupoG, DATEADD(DAY, 4, SYSUTCDATETIME()), DATEADD(MINUTE, 4 * 1440 + 120, SYSUTCDATETIME()), N'UTC_GENERADOR'),
           (@sMan2, N'SMN manual 2', 903, N'SMN903', 1, @grupoG, DATEADD(DAY, 5, SYSUTCDATETIME()), DATEADD(MINUTE, 5 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2'),
           (@sV1,   N'SMN manual v1', 904, N'SMN904', 1, @grupoG, DATEADD(DAY, 6, SYSUTCDATETIME()), DATEADD(MINUTE, 6 * 1440 + 120, SYSUTCDATETIME()), NULL),
           (@sOwner, N'SMN owner',   905, N'SMN905', 1, @grupoG, DATEADD(DAY, 7, SYSUTCDATETIME()), DATEADD(MINUTE, 7 * 1440 + 120, SYSUTCDATETIME()), N'UTC_OWNER');
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_manual WHERE idGrupo = @grupoG) <> 3 OR EXISTS (SELECT 1 FROM dbo.uv_sesion_manual WHERE idSesion IN (@sGen, @sOwner))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_manual WHERE idSesion = @sV1)
        THROW 58005, 'TEST FAILED CULM001_SMN_02: uv_sesion_manual debe incluir las sesiones de v1 (NULL) y v2 (UTC_V2) y excluir UTC_GENERADOR y UTC_OWNER.', 1;

    CREATE TABLE #dest (tipoDestinatario NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
        nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2);

    -- SMN-01: 3 estudiantes activos + 2 coordinadores (grupo mixto A/B)
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sMan, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #dest WHERE tipoDestinatario = N'ESTUDIANTE') <> 3
       OR (SELECT COUNT(*) FROM #dest WHERE tipoDestinatario = N'COORDINADOR') <> 2
       OR NOT EXISTS (SELECT 1 FROM #dest WHERE tipoDestinatario = N'COORDINADOR' AND idUsuario = @uCA)
       OR NOT EXISTS (SELECT 1 FROM #dest WHERE tipoDestinatario = N'COORDINADOR' AND idUsuario = @uCB)
       OR NOT EXISTS (SELECT 1 FROM #dest WHERE tipoDestinatario = N'ESTUDIANTE' AND idUsuario = @uE0)
       OR EXISTS (SELECT 1 FROM #dest WHERE correo IS NULL OR nombreAsignatura IS NULL OR nombreDocente IS NULL OR fechaHoraInicio IS NULL)
        THROW 58010, 'TEST FAILED CULM001_SMN_01: el grupo mixto debe notificar a 3 estudiantes y a los 2 coordinadores.', 1;
    TRUNCATE TABLE #dest;
    PRINT 'TEST_PASS:CULM001_SMN_01_DESTINATARIOS_GRUPO_MIXTO';

    -- SMN-02: sesion no manual => sin destinatarios
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sGen, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF EXISTS (SELECT 1 FROM #dest) THROW 58011, 'TEST FAILED CULM001_SMN_02: una sesion no manual no tiene destinatarios.', 1;
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sV1, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #dest) <> 5 THROW 58015, 'TEST FAILED CULM001_SMN_01: la sesion creada por v1 (procedencia NULL) tambien notifica a 3 estudiantes y 2 coordinadores.', 1;
    TRUNCATE TABLE #dest;
    PRINT 'TEST_PASS:CULM001_SMN_02_SESION_NO_MANUAL_SIN_DESTINATARIOS';

    -- SMN-01b: un coordinador de dos programas es UNA fila (CA coordina A y B)
    DECLARE @coordCA UNIQUEIDENTIFIER = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCA);
    DECLARE @coordCB UNIQUEIDENTIFIER = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCB);
    UPDATE dbo.Programa SET coordinador = @coordCA WHERE id = @progB;
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sMan, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #dest WHERE tipoDestinatario = N'COORDINADOR') <> 1 OR NOT EXISTS (SELECT 1 FROM #dest WHERE tipoDestinatario = N'COORDINADOR' AND idUsuario = @uCA)
        THROW 58013, 'TEST FAILED CULM001_SMN_01: un coordinador de dos programas debe recibir una sola notificacion.', 1;
    TRUNCATE TABLE #dest;
    PRINT 'TEST_PASS:CULM001_SMN_01_COORDINADOR_DOS_PROGRAMAS_UNA_FILA';

    -- SMN-04: coordinador inactivo no es destinatario (B vuelve a CB, que queda inactivo)
    UPDATE dbo.Programa SET coordinador = @coordCB WHERE id = @progB;
    UPDATE dbo.Coordinador SET estado = 0 WHERE id = @coordCB;
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sMan, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #dest WHERE tipoDestinatario = N'COORDINADOR') <> 1 OR EXISTS (SELECT 1 FROM #dest WHERE idUsuario = @uCB)
        THROW 58014, 'TEST FAILED CULM001_SMN_04: un coordinador inactivo no debe recibir la notificacion.', 1;
    TRUNCATE TABLE #dest;
    UPDATE dbo.Coordinador SET estado = 1 WHERE id = @coordCB;
    PRINT 'TEST_PASS:CULM001_SMN_04_COORDINADOR_INACTIVO_OMITIDO';

    -- ---- cancelacion por el coordinador ----
    CREATE TABLE #can (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL, totalEstudiantesActivos INT NULL);
    DECLARE @motivo NVARCHAR(50) = (SELECT TOP 1 codigo FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    DECLARE @nombreMotivo NVARCHAR(200) = (SELECT TOP 1 nombre FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    DECLARE @tran INT = @@TRANCOUNT;

    -- coordinador sin programas del grupo (CX)
    DECLARE @uCX UNIQUEIDENTIFIER = NEWID(), @coordCX UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uCX, @tipoCC, 1950000099, N'SMN', N'', N'CoordX', N'', N'smn.coordx@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordCX, @uCX, 1, @fac);

    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCX;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%' AND idSesion IS NULL)
       OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan)
        THROW 58020, 'TEST FAILED CULM001_SMN_06: un coordinador fuera de ambito debe recibir SEC_002 sin escrituras.', 1;
    TRUNCATE TABLE #can;

    -- el docente titular no puede usar el SP del coordinador => SEC_001
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan)
        THROW 58021, 'TEST FAILED CULM001_SMN_06: el docente no puede cancelar por la via del coordinador (SEC_001).', 1;
    TRUNCATE TABLE #can;

    -- sesion no manual => SES_018
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sGen, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]018|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sGen)
        THROW 58022, 'TEST FAILED CULM001_SMN_06: una sesion no manual debe responder SES_018.', 1;
    TRUNCATE TABLE #can;

    -- motivo fuera de catalogo / nulo => SES_019
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = N'NO_EXISTE', @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = NULL, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]019|%') <> 2 OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan)
        THROW 58023, 'TEST FAILED CULM001_SMN_06: un motivo fuera del catalogo debe responder SES_019.', 1;
    TRUNCATE TABLE #can;

    -- observacion demasiado larga => SES_021
    DECLARE @obsLarga NVARCHAR(4000) = REPLICATE(N'y', 4000);
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan2, @codigoMotivo = @motivo, @observacion = @obsLarga, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]021|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan2)
        THROW 58024, 'TEST FAILED CULM001_SMN_06: una observacion demasiado larga debe responder SES_021.', 1;
    TRUNCATE TABLE #can;
    PRINT 'TEST_PASS:CULM001_SMN_06_RECHAZOS';

    -- SMN-05: CA cancela la manual del grupo mixto con observacion recortada
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = @motivo, @observacion = N'  Aviso fuera de calendario  ', @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]020|%' AND idSesion = @sMan AND idGrupo = @grupoG
                   AND fechaCancelacionUtc IS NOT NULL AND totalEstudiantesActivos = 3 AND idCorrelacion = @c)
        THROW 58030, 'TEST FAILED CULM001_SMN_05: la cancelacion del coordinador debe responder SES_020 con la sesion, el grupo y 3 estudiantes activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                   WHERE sc.sesion = @sMan AND t.esAutomatica = 0 AND sc.usuarioEjecutor = @uCA AND sc.diaFestivo IS NULL AND sc.idCorrelacion = @c
                     AND sc.motivo = CONCAT(@nombreMotivo, N': Aviso fuera de calendario'))
        THROW 58031, 'TEST FAILED CULM001_SMN_05: la fila de SesionCancelacion no refleja motivo del catalogo + observacion recortada, ejecutor y correlacion.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sMan AND estaCancelada = 1 AND idUsuarioCancelacion = @uCA)
        THROW 58032, 'TEST FAILED CULM001_SMN_05: uv_sesion_estado no refleja la cancelacion del coordinador.', 1;
    IF @@TRANCOUNT <> @tran THROW 58033, 'TEST FAILED CULM001_SMN_05: el SP no debe alterar el nivel de transacciones.', 1;
    TRUNCATE TABLE #can;

    -- doble cancelacion => SES_011 y motivo original intacto
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]011|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan AND motivo = CONCAT(@nombreMotivo, N': Aviso fuera de calendario'))
        THROW 58034, 'TEST FAILED CULM001_SMN_06: la segunda cancelacion debe responder SES_011 y conservar el motivo original.', 1;
    TRUNCATE TABLE #can;
    PRINT 'TEST_PASS:CULM001_SMN_05_COORDINADOR_CANCELA';

    -- el otro coordinador del grupo mixto tambien puede cancelar; sin observacion el motivo es solo el nombre del catalogo
    INSERT #can EXEC dbo.usp_cancelar_sesion_coordinador @idSesion = @sMan2, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #can WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sMan2 AND motivo = @nombreMotivo AND usuarioEjecutor = @uCB)
        THROW 58035, 'TEST FAILED CULM001_SMN_05: el otro coordinador del grupo mixto puede cancelar; sin observacion el motivo es solo el nombre del catalogo.', 1;
    TRUNCATE TABLE #can;
    PRINT 'TEST_PASS:CULM001_SMN_05_GRUPO_MIXTO_SEGUNDO_COORDINADOR';

    -- SMN-07: consulta de motivos (COORDINADOR) y rechazo a otros perfiles
    CREATE TABLE #mot (codigo NVARCHAR(50), nombre NVARCHAR(200));
    INSERT #mot EXEC dbo.usp_consultar_motivos_cancelacion_sesion @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mot) <> (SELECT COUNT(*) FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1) OR NOT EXISTS (SELECT 1 FROM #mot WHERE codigo = @motivo)
        THROW 58040, 'TEST FAILED CULM001_SMN_07: la consulta de motivos debe devolver los motivos activos.', 1;
    PRINT 'TEST_PASS:CULM001_SMN_07_MOTIVOS';

    PRINT 'TEST_PASS:CULM001_SESIONES_MANUALES_NOTIFICACION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58099, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- SMN-03 / SMN-07 (rechazos por THROW 51000): fuera de la transaccion principal, porque el THROW de un SP de consulta con
-- SET XACT_ABORT ON condena la transaccion del llamador. Cada caso corre en su propia transaccion que se revierte.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @sMan UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000) = NULL;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sMan, N'SMN manual', 901, N'SMN901', 1, @grupoG, DATEADD(DAY, 3, SYSUTCDATETIME()), DATEADD(MINUTE, 3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2');
    CREATE TABLE #d (tipoDestinatario NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
        nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2);
    CREATE TABLE #m (codigo NVARCHAR(50), nombre NVARCHAR(200));

    -- SMN-03: un coordinador no consulta los destinatarios (SEC_001: no es docente)
    BEGIN TRY
        INSERT #d EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sMan, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%' OR EXISTS (SELECT 1 FROM #d)
        THROW 58012, 'TEST FAILED CULM001_SMN_03: un coordinador no puede consultar los destinatarios (SEC_001).', 1;
    PRINT 'TEST_PASS:CULM001_SMN_03_SOLO_DOCENTE';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg1 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58098, @msg1, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c2 UNIQUEIDENTIFIER = NEWID(), @err2 NVARCHAR(4000) = NULL;
    CREATE TABLE #m2 (codigo NVARCHAR(50), nombre NVARCHAR(200));
    -- SMN-07: la consulta de motivos es solo del coordinador (SEC_001 para el docente)
    BEGIN TRY
        INSERT #m2 EXEC dbo.usp_consultar_motivos_cancelacion_sesion @idUsuarioEjecutor = @uT, @idCorrelacion = @c2;
    END TRY
    BEGIN CATCH
        SET @err2 = ERROR_MESSAGE();
    END CATCH;
    IF @err2 IS NULL OR @err2 NOT LIKE N'%DBCODE=SEC[_]001|%' OR EXISTS (SELECT 1 FROM #m2)
        THROW 58041, 'TEST FAILED CULM001_SMN_07: la consulta de motivos es solo del coordinador (SEC_001).', 1;
    PRINT 'TEST_PASS:CULM001_SMN_07_MOTIVOS_SOLO_COORDINADOR';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg2 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58097, @msg2, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58096, 'TEST FAILED CULM001_SMN: quedaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:CULM001_SMN_TRANCOUNT_ZERO';
PRINT 'TEST END: test_sesiones_manuales_notificacion';
GO
