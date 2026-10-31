USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_marcar_notificacion_entregada (NOTIF-001)';
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
    DECLARE @idEntregada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA');
    DECLARE @corr UNIQUEIDENTIFIER;
    DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();
    DECLARE @instanciaA NVARCHAR(100) = N'worker-host-a';
    DECLARE @instanciaB NVARCHAR(100) = N'worker-host-b';

    -- DB-M01: Reserva vigente de la misma instancia -> ENTREGADA, GEN_005
    PRINT '-> DB-M01: marcar entregada exitosa';
    DECLARE @id1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, codigoError, detalleError, idCorrelacion)
    VALUES (@id1, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, 'ERR_PREV', N'Detalle previo', NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @id1,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_005|%')
        THROW 53201, 'TEST FAILED DB-M01: no retorno exito con GEN_005.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.NotificacionSaliente
        WHERE id = @id1
          AND idEstado = @idEntregada
          AND entregadoEn IS NOT NULL
          AND reservadoHasta IS NULL
          AND reservadoPor IS NULL
          AND codigoError IS NULL
          AND detalleError IS NULL
    )
        THROW 53202, 'TEST FAILED DB-M01: fila no paso a ENTREGADA o no limpio reservas/errores.', 1;
    PRINT 'TEST_PASS:DB-M01';
    TRUNCATE TABLE #r;

    -- DB-M02: id inexistente -> NTF_002
    PRINT '-> DB-M02: id inexistente';
    SET @corr = NEWID();
    DECLARE @idInexistente UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @idInexistente,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_002|%')
        THROW 53203, 'TEST FAILED DB-M02: no rechazo id inexistente con NTF_002.', 1;
    PRINT 'TEST_PASS:DB-M02';
    TRUNCATE TABLE #r;

    -- DB-M03: otra instancia -> NTF_003 y no cambia
    PRINT '-> DB-M03: otra instancia rechazada con NTF_003';
    DECLARE @id3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@id3, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -5, @ahora), DATEADD(MINUTE, 5, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @id3,
        @instancia = @instanciaB,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_003|%')
        THROW 53204, 'TEST FAILED DB-M03: no rechazo otra instancia con NTF_003.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id3 AND idEstado = @idReservada AND reservadoPor = @instanciaA)
        THROW 53205, 'TEST FAILED DB-M03: la fila fue modificada a pesar del rechazo.', 1;
    PRINT 'TEST_PASS:DB-M03';
    TRUNCATE TABLE #r;

    -- DB-M04: reserva vencida -> NTF_003
    PRINT '-> DB-M04: reserva vencida rechazada con NTF_003';
    DECLARE @id4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, reservadoHasta, reservadoPor, idCorrelacion)
    VALUES (@id4, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(MINUTE, -15, @ahora), DATEADD(MINUTE, -1, @ahora), @instanciaA, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @id4,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_003|%')
        THROW 53206, 'TEST FAILED DB-M04: no rechazo reserva vencida con NTF_003.', 1;
    PRINT 'TEST_PASS:DB-M04';
    TRUNCATE TABLE #r;

    -- DB-M05: ya ENTREGADA -> NTF_003
    PRINT '-> DB-M05: ya entregada rechazada con NTF_003';
    DECLARE @id5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, entregadoEn, idCorrelacion)
    VALUES (@id5, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(MINUTE, -15, @ahora), @ahora, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @id5,
        @instancia = @instanciaA,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_003|%')
        THROW 53207, 'TEST FAILED DB-M05: no rechazo notificacion ya ENTREGADA con NTF_003.', 1;
    PRINT 'TEST_PASS:DB-M05';
    TRUNCATE TABLE #r;

    -- DB-M06: correlacion nula -> CORR_001
    PRINT '-> DB-M06: correlacion nula rechazada con CORR_001';
    INSERT INTO #r EXEC dbo.usp_marcar_notificacion_entregada
        @id = @id1,
        @instancia = @instanciaA,
        @idCorrelacion = NULL;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 53208, 'TEST FAILED DB-M06: no rechazo correlacion nula con CORR_001.', 1;
    PRINT 'TEST_PASS:DB-M06';

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
    THROW 53299, 'TEST FAILED: test_usp_marcar_notificacion_entregada dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_marcar_notificacion_entregada (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_MARCAR_NOTIFICACION_ENTREGADA';
GO
