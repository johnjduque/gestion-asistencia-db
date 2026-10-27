USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_registrar_fallo_notificacion (NOTIF-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    DECLARE @idReservada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');
    DECLARE @idReintentable UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE');
    DECLARE @idDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');

    DECLARE @instanciaA NVARCHAR(100) = N'worker-host-a';
    DECLARE @instanciaB NVARCHAR(100) = N'worker-host-b';
    DECLARE @corr UNIQUEIDENTIFIER;
    DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();

    -- DB-F01: Reintentable, intentos=1, base=30, max=900 -> FALLIDA_REINTENTABLE, proximoIntentoEn ≈ ahora + 30s
    PRINT '-> DB-F01: fallo reintentable intento 1';
    DECLARE @idF1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF1, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF1,
        @instancia = @instanciaA,
        @codigoError = 'TIMEOUT',
        @detalleError = N'Conexion agotada',
        @reintentable = 1,
        @maxIntentos = 5,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_005|%')
        THROW 53301, 'TEST FAILED DB-F01: no retorno exito con GEN_005.', 1;

    DECLARE @proxF1 DATETIMEOFFSET(7);
    SELECT @proxF1 = proximoIntentoEn FROM dbo.NotificacionSaliente WHERE id = @idF1 AND idEstado = @idReintentable AND reservadoHasta IS NULL AND reservadoPor IS NULL AND codigoError = 'TIMEOUT';
    IF @proxF1 IS NULL OR ABS(DATEDIFF(SECOND, @ahora, @proxF1) - 30) > 5
        THROW 53302, 'TEST FAILED DB-F01: proximoIntentoEn no corresponde a ahora + 30s.', 1;
    PRINT 'TEST_PASS:DB-F01';
    TRUNCATE TABLE #r;

    -- DB-F02: intentos=2 -> +60s
    PRINT '-> DB-F02: backoff exponencial intento 2 (+60s)';
    DECLARE @idF2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF2, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 2, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF2,
        @instancia = @instanciaA,
        @codigoError = 'TIMEOUT',
        @detalleError = N'Conexion agotada 2',
        @reintentable = 1,
        @maxIntentos = 5,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    DECLARE @proxF2 DATETIMEOFFSET(7);
    SELECT @proxF2 = proximoIntentoEn FROM dbo.NotificacionSaliente WHERE id = @idF2;
    IF @proxF2 IS NULL OR ABS(DATEDIFF(SECOND, @ahora, @proxF2) - 60) > 5
        THROW 53303, 'TEST FAILED DB-F02: proximoIntentoEn para intento 2 no corresponde a +60s.', 1;
    PRINT 'TEST_PASS:DB-F02';
    TRUNCATE TABLE #r;

    -- DB-F03: intentos tal que base*2^(intentos-1) > max -> se aplica el tope max
    PRINT '-> DB-F03: aplicacion de tope maxIntentos';
    DECLARE @idF3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF3, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 10, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF3,
        @instancia = @instanciaA,
        @codigoError = 'TIMEOUT',
        @detalleError = N'Conexion agotada 10',
        @reintentable = 1,
        @maxIntentos = 20,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    DECLARE @proxF3 DATETIMEOFFSET(7);
    SELECT @proxF3 = proximoIntentoEn FROM dbo.NotificacionSaliente WHERE id = @idF3;
    IF @proxF3 IS NULL OR ABS(DATEDIFF(SECOND, @ahora, @proxF3) - 900) > 5
        THROW 53304, 'TEST FAILED DB-F03: no aplico el tope de backoffMaxSegundos (900s).', 1;
    PRINT 'TEST_PASS:DB-F03';
    TRUNCATE TABLE #r;

    -- DB-F04: intentos >= maxIntentos -> FALLIDA_DEFINITIVA
    PRINT '-> DB-F04: intentos >= maxIntentos pasa a FALLIDA_DEFINITIVA';
    DECLARE @idF4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF4, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 5, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF4,
        @instancia = @instanciaA,
        @codigoError = 'MAX_RETRY',
        @detalleError = N'Agotados intentos',
        @reintentable = 1,
        @maxIntentos = 5,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idF4 AND idEstado = @idDefinitiva AND proximoIntentoEn IS NULL)
        THROW 53305, 'TEST FAILED DB-F04: no paso a FALLIDA_DEFINITIVA tras alcanzar maxIntentos.', 1;
    PRINT 'TEST_PASS:DB-F04';
    TRUNCATE TABLE #r;

    -- DB-F05: @reintentable = 0 -> FALLIDA_DEFINITIVA aunque queden intentos
    PRINT '-> DB-F05: fallo no reintentable';
    DECLARE @idF5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF5, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF5,
        @instancia = @instanciaA,
        @codigoError = 'BAD_DEST',
        @detalleError = N'Destinatario no existe',
        @reintentable = 0,
        @maxIntentos = 5,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idF5 AND idEstado = @idDefinitiva)
        THROW 53306, 'TEST FAILED DB-F05: no paso a FALLIDA_DEFINITIVA con @reintentable=0.', 1;
    PRINT 'TEST_PASS:DB-F05';
    TRUNCATE TABLE #r;

    -- DB-F06: detalleError de 500 caracteres -> truncado a 300
    PRINT '-> DB-F06: detalleError truncado a 300 caracteres';
    DECLARE @idF6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF6, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    DECLARE @detalleLargo NVARCHAR(600) = REPLICATE(N'D', 500);
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion
        @id = @idF6,
        @instancia = @instanciaA,
        @codigoError = 'TRUNC_TEST',
        @detalleError = @detalleLargo,
        @reintentable = 1,
        @maxIntentos = 5,
        @backoffBaseSegundos = 30,
        @backoffMaxSegundos = 900,
        @idCorrelacion = @corr;

    DECLARE @detGuardado NVARCHAR(400);
    SELECT @detGuardado = detalleError FROM dbo.NotificacionSaliente WHERE id = @idF6;
    IF LEN(@detGuardado) <> 300
        THROW 53307, 'TEST FAILED DB-F06: detalleError no fue truncado exactamente a 300.', 1;
    PRINT 'TEST_PASS:DB-F06';
    TRUNCATE TABLE #r;

    -- DB-F07: parametros invalidos (@reintentable nulo; maxIntentos 0/21; base 0; max < base)
    PRINT '-> DB-F07: parametros invalidos rechazados con NTF_001';
    DECLARE @idF7 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF7, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    -- reintentable nulo
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idF7, @instancia = @instanciaA, @codigoError = 'E', @detalleError = 'D', @reintentable = NULL, @maxIntentos = 5, @backoffBaseSegundos = 30, @backoffMaxSegundos = 900, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53308, 'TEST FAILED DB-F07: no rechazo @reintentable nulo con NTF_001.', 1;
    TRUNCATE TABLE #r;

    -- maxIntentos 0
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idF7, @instancia = @instanciaA, @codigoError = 'E', @detalleError = 'D', @reintentable = 1, @maxIntentos = 0, @backoffBaseSegundos = 30, @backoffMaxSegundos = 900, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53309, 'TEST FAILED DB-F07: no rechazo @maxIntentos 0 con NTF_001.', 1;
    TRUNCATE TABLE #r;

    -- max < base
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idF7, @instancia = @instanciaA, @codigoError = 'E', @detalleError = 'D', @reintentable = 1, @maxIntentos = 5, @backoffBaseSegundos = 60, @backoffMaxSegundos = 30, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53310, 'TEST FAILED DB-F07: no rechazo backoffMax < backoffBase con NTF_001.', 1;
    PRINT 'TEST_PASS:DB-F07';
    TRUNCATE TABLE #r;

    -- DB-F08: Id inexistente (NTF_002); otra instancia (NTF_003); reserva vencida (NTF_003)
    PRINT '-> DB-F08: id inexistente, otra instancia o reserva vencida';
    SET @corr = NEWID();
    DECLARE @idInexistente UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idInexistente, @instancia = @instanciaA, @codigoError = 'E', @detalleError = 'D', @reintentable = 1, @maxIntentos = 5, @backoffBaseSegundos = 30, @backoffMaxSegundos = 900, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_002|%')
        THROW 53311, 'TEST FAILED DB-F08: no rechazo id inexistente con NTF_002.', 1;
    TRUNCATE TABLE #r;

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idF7, @instancia = @instanciaB, @codigoError = 'E', @detalleError = 'D', @reintentable = 1, @maxIntentos = 5, @backoffBaseSegundos = 30, @backoffMaxSegundos = 900, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_003|%')
        THROW 53312, 'TEST FAILED DB-F08: no rechazo otra instancia con NTF_003.', 1;
    TRUNCATE TABLE #r;

    -- reserva vencida
    DECLARE @idF8Venc UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@idF8Venc, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -15, @ahora), DATEADD(MINUTE, -1, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_fallo_notificacion @id = @idF8Venc, @instancia = @instanciaA, @codigoError = 'E', @detalleError = 'D', @reintentable = 1, @maxIntentos = 5, @backoffBaseSegundos = 30, @backoffMaxSegundos = 900, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_003|%')
        THROW 53313, 'TEST FAILED DB-F08: no rechazo reserva vencida con NTF_003.', 1;
    PRINT 'TEST_PASS:DB-F08';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53399, 'TEST FAILED: test_usp_registrar_fallo_notificacion dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_registrar_fallo_notificacion (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_REGISTRAR_FALLO_NOTIFICACION';
GO
