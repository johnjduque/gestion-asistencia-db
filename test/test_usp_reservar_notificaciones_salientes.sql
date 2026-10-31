USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_reservar_notificaciones_salientes (NOTIF-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #reservadas (
        id            UNIQUEIDENTIFIER,
        tipo          VARCHAR(60),
        asunto        NVARCHAR(200),
        mensaje       NVARCHAR(4000),
        destinatarios NVARCHAR(MAX),
        datos         NVARCHAR(MAX),
        intentos      INT,
        creadoEn      DATETIMEOFFSET(7),
        idCorrelacion UNIQUEIDENTIFIER,
        traceId       CHAR(32),
        spanId        CHAR(16)
    );

    DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
    DECLARE @idReservada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');
    DECLARE @idReintentable UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE');
    DECLARE @idEntregada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA');
    DECLARE @idDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');

    DECLARE @instanciaA NVARCHAR(100) = N'worker-host-a';
    DECLARE @instanciaB NVARCHAR(100) = N'worker-host-b';
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();

    -- DB-R01 & DB-R09 & DB-R10: 3 PENDIENTE, lote=2, orden creadoEn ASC, columnas exactas
    PRINT '-> DB-R01 / R09 / R10: reserva lote 2 de 3 PENDIENTES';
    DECLARE @id1 UNIQUEIDENTIFIER = NEWID(), @id2 UNIQUEIDENTIFIER = NEWID(), @id3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, proximoIntentoEn, idCorrelacion)
    VALUES
        (@id1, 'TIPO_A', N'Asunto 1', N'Msg 1', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idPendiente, 0, DATEADD(MINUTE, -10, @ahora), DATEADD(MINUTE, -10, @ahora), @corr),
        (@id2, 'TIPO_B', N'Asunto 2', N'Msg 2', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idPendiente, 0, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, -5, @ahora), @corr),
        (@id3, 'TIPO_C', N'Asunto 3', N'Msg 3', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idPendiente, 0, @ahora, @ahora, @corr);

    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes
        @lote = 2,
        @leaseSegundos = 60,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF (SELECT COUNT(*) FROM #reservadas) <> 2
        THROW 53101, 'TEST FAILED DB-R01: no devolvio exactamente 2 filas.', 1;

    -- Verificar orden ascendente: id1 es mas antiguo que id2
    DECLARE @firstId UNIQUEIDENTIFIER, @secondId UNIQUEIDENTIFIER;
    SELECT TOP 1 @firstId = id FROM #reservadas;
    IF @firstId <> @id1
        THROW 53102, 'TEST FAILED DB-R09: no ordeno por creadoEn ascendente.', 1;

    -- Verificar que pasaron a RESERVADA con intentos=1 y datos de lease
    IF NOT EXISTS (
        SELECT 1 FROM dbo.NotificacionSaliente
        WHERE id = @id1
          AND idEstado = @idReservada
          AND intentos = 1
          AND reservadoPor = @instanciaA
          AND reservadoHasta > @ahora
    )
        THROW 53103, 'TEST FAILED DB-R01: fila 1 no paso a RESERVADA con intentos=1.', 1;

    -- DB-R10: verificar columnas
    IF NOT EXISTS (SELECT 1 FROM #reservadas WHERE id = @id1 AND tipo = 'TIPO_A' AND asunto = N'Asunto 1' AND intentos = 1)
        THROW 53104, 'TEST FAILED DB-R10: columnas devueltas no coinciden.', 1;

    PRINT 'TEST_PASS:DB-R01';
    PRINT 'TEST_PASS:DB-R09';
    PRINT 'TEST_PASS:DB-R10';
    TRUNCATE TABLE #reservadas;

    -- DB-R02 & DB-R03: FALLIDA_REINTENTABLE con proximoIntentoEn futuro (no) vs pasado (si)
    PRINT '-> DB-R02 / DB-R03: FALLIDA_REINTENTABLE segun proximoIntentoEn';
    DECLARE @idReintFuturo UNIQUEIDENTIFIER = NEWID();
    DECLARE @idReintPasado UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, proximoIntentoEn, idCorrelacion)
    VALUES
        (@idReintFuturo, 'TIPO_FUT', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReintentable, 1, DATEADD(MINUTE, -20, @ahora), DATEADD(HOUR, 1, @ahora), @corr),
        (@idReintPasado, 'TIPO_PAS', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReintentable, 1, DATEADD(MINUTE, -20, @ahora), DATEADD(MINUTE, -1, @ahora), @corr);

    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes
        @lote = 10,
        @leaseSegundos = 60,
        @instancia = @instanciaB,
        @idCorrelacion = @corr;

    IF EXISTS (SELECT 1 FROM #reservadas WHERE id = @idReintFuturo)
        THROW 53105, 'TEST FAILED DB-R02: reservo fila con proximoIntentoEn futuro.', 1;
    PRINT 'TEST_PASS:DB-R02';

    IF NOT EXISTS (SELECT 1 FROM #reservadas WHERE id = @idReintPasado)
        THROW 53106, 'TEST FAILED DB-R03: no reservo fila con proximoIntentoEn pasado.', 1;
    PRINT 'TEST_PASS:DB-R03';
    TRUNCATE TABLE #reservadas;

    -- DB-R04 & DB-R05: RESERVADA vencida (recupera e incrementa intento) vs vigente (no recupera)
    PRINT '-> DB-R04 / DB-R05: RESERVADA vencida vs vigente';
    DECLARE @idResVencida UNIQUEIDENTIFIER = NEWID();
    DECLARE @idResVigente UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES
        (@idResVencida, 'TIPO_VENC', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -30, @ahora), DATEADD(MINUTE, -5, @ahora), N'worker-dead', @corr),
        (@idResVigente, 'TIPO_VIG', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -30, @ahora), DATEADD(MINUTE, 20, @ahora), N'worker-live', @corr);

    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes
        @lote = 10,
        @leaseSegundos = 60,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #reservadas WHERE id = @idResVencida AND intentos = 2)
        THROW 53107, 'TEST FAILED DB-R04: no recupero reserva vencida o no incremento intento a 2.', 1;
    PRINT 'TEST_PASS:DB-R04';

    IF EXISTS (SELECT 1 FROM #reservadas WHERE id = @idResVigente)
        THROW 53108, 'TEST FAILED DB-R05: reservo fila con reserva vigente.', 1;
    PRINT 'TEST_PASS:DB-R05';
    TRUNCATE TABLE #reservadas;

    -- DB-R06: Filas ENTREGADA y FALLIDA_DEFINITIVA nunca se devuelven
    PRINT '-> DB-R06: terminales nunca se devuelven';
    DECLARE @idEnt UNIQUEIDENTIFIER = NEWID(), @idDef UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, entregadoEn, idCorrelacion)
    VALUES
        (@idEnt, 'TIPO_E', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -2, @ahora), @ahora, @corr),
        (@idDef, 'TIPO_D', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idDefinitiva, 5, DATEADD(DAY, -2, @ahora), NULL, @corr);

    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes
        @lote = 10,
        @leaseSegundos = 60,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF EXISTS (SELECT 1 FROM #reservadas WHERE id IN (@idEnt, @idDef))
        THROW 53109, 'TEST FAILED DB-R06: devolvio fila en estado terminal.', 1;
    PRINT 'TEST_PASS:DB-R06';
    TRUNCATE TABLE #reservadas;

    -- DB-R07: Validacion de parametros (lote 0/501, lease 4/3601, instancia nula/vacia, correlacion nula)
    PRINT '-> DB-R07: parametros invalidos';
    DECLARE @falloParam BIT = 0;
    BEGIN TRY
        EXEC dbo.usp_reservar_notificaciones_salientes @lote = 0, @leaseSegundos = 60, @instancia = @instanciaA, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @falloParam = 1;
    END CATCH;
    IF @falloParam <> 1 THROW 53110, 'TEST FAILED DB-R07: no fallo con lote 0.', 1;

    SET @falloParam = 0;
    BEGIN TRY
        EXEC dbo.usp_reservar_notificaciones_salientes @lote = 501, @leaseSegundos = 60, @instancia = @instanciaA, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @falloParam = 1;
    END CATCH;
    IF @falloParam <> 1 THROW 53111, 'TEST FAILED DB-R07: no fallo con lote 501.', 1;

    SET @falloParam = 0;
    BEGIN TRY
        EXEC dbo.usp_reservar_notificaciones_salientes @lote = 10, @leaseSegundos = 4, @instancia = @instanciaA, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @falloParam = 1;
    END CATCH;
    IF @falloParam <> 1 THROW 53112, 'TEST FAILED DB-R07: no fallo con lease < 5.', 1;

    SET @falloParam = 0;
    BEGIN TRY
        EXEC dbo.usp_reservar_notificaciones_salientes @lote = 10, @leaseSegundos = 60, @instancia = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @falloParam = 1;
    END CATCH;
    IF @falloParam <> 1 THROW 53113, 'TEST FAILED DB-R07: no fallo con instancia nula.', 1;

    SET @falloParam = 0;
    BEGIN TRY
        EXEC dbo.usp_reservar_notificaciones_salientes @lote = 10, @leaseSegundos = 60, @instancia = @instanciaA, @idCorrelacion = NULL;
    END TRY
    BEGIN CATCH
        SET @falloParam = 1;
    END CATCH;
    IF @falloParam <> 1 THROW 53114, 'TEST FAILED DB-R07: no fallo con correlacion nula.', 1;
    PRINT 'TEST_PASS:DB-R07';

    -- DB-R08: Sin elegibles -> conjunto vacio
    PRINT '-> DB-R08: sin elegibles retorna conjunto vacio';
    -- Reservar el ultimo que quedaba (@id3)
    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes @lote = 10, @leaseSegundos = 60, @instancia = @instanciaA, @idCorrelacion = @corr;
    TRUNCATE TABLE #reservadas;

    -- Ahora no debe quedar ningun elegible
    INSERT INTO #reservadas
    EXEC dbo.usp_reservar_notificaciones_salientes @lote = 10, @leaseSegundos = 60, @instancia = @instanciaA, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #reservadas) <> 0
        THROW 53115, 'TEST FAILED DB-R08: no retorno conjunto vacio cuando no hay elegibles.', 1;
    PRINT 'TEST_PASS:DB-R08';

    DROP TABLE #reservadas;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53199, 'TEST FAILED: test_usp_reservar_notificaciones_salientes dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_reservar_notificaciones_salientes (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_RESERVAR_NOTIFICACIONES_SALIENTES';
GO
