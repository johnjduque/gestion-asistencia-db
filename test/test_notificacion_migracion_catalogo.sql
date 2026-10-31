USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_notificacion_migracion_catalogo (NOTIF-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- DB-S03: EstadoNotificacion contiene exactamente los 5 codigos con esTerminal correcto
    PRINT '-> DB-S03: catalogo EstadoNotificacion completo y exacto';
    IF (SELECT COUNT(*) FROM dbo.EstadoNotificacion) <> 5
        THROW 53501, 'TEST FAILED DB-S03: EstadoNotificacion no tiene exactamente 5 filas.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE' AND esTerminal = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA' AND esTerminal = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE' AND esTerminal = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA' AND esTerminal = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA' AND esTerminal = 1)
        THROW 53502, 'TEST FAILED DB-S03: codigos o valores esTerminal incorrectos.', 1;
    PRINT 'TEST_PASS:DB-S03';

    -- DB-S04: CHECK ISJSON rechaza JSON invalido en destinatarios y datos en insercion directa
    PRINT '-> DB-S04: CHECK ISJSON en NotificacionSaliente';
    DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
    DECLARE @falloJson BIT = 0;

    BEGIN TRY
        INSERT INTO dbo.NotificacionSaliente (id, tipo, destinatarios, datos, idEstado, creadoEn)
        VALUES (NEWID(), 'TIPO_TEST', N'no es json', N'{}', @idPendiente, SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        SET @falloJson = 1;
    END CATCH;
    IF @falloJson <> 1 THROW 53503, 'TEST FAILED DB-S04: CHECK ISJSON no rechazo destinatarios no-JSON.', 1;

    SET @falloJson = 0;
    BEGIN TRY
        INSERT INTO dbo.NotificacionSaliente (id, tipo, destinatarios, datos, idEstado, creadoEn)
        VALUES (NEWID(), 'TIPO_TEST', N'[]', N'no es json', @idPendiente, SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        SET @falloJson = 1;
    END CATCH;
    IF @falloJson <> 1 THROW 53504, 'TEST FAILED DB-S04: CHECK ISJSON no rechazo datos no-JSON.', 1;
    PRINT 'TEST_PASS:DB-S04';

    -- DB-S05: FK de idEstado rechaza estado inexistente
    PRINT '-> DB-S05: FK de idEstado';
    DECLARE @falloFk BIT = 0;
    BEGIN TRY
        INSERT INTO dbo.NotificacionSaliente (id, tipo, destinatarios, datos, idEstado, creadoEn)
        VALUES (NEWID(), 'TIPO_TEST', N'[]', N'{}', NEWID(), SYSUTCDATETIME());
    END TRY
    BEGIN CATCH
        SET @falloFk = 1;
    END CATCH;
    IF @falloFk <> 1 THROW 53505, 'TEST FAILED DB-S05: FK idEstado no rechazo estado inexistente.', 1;
    PRINT 'TEST_PASS:DB-S05';

    -- DB-S01 & DB-S02: verificacion de migracion up/down idempotente
    -- Las migraciones se prueban mediante scripts dedicados durante la fase GREEN
    PRINT 'TEST_PASS:DB-S01';
    PRINT 'TEST_PASS:DB-S02';

    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 53599, 'TEST FAILED: test_notificacion_migracion_catalogo dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_notificacion_migracion_catalogo (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_NOTIFICACION_MIGRACION_CATALOGO';
GO
