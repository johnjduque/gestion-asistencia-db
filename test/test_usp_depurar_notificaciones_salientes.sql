USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_depurar_notificaciones_salientes (NOTIF-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT,
        eliminadas              INT
    );

    DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
    DECLARE @idReservada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');
    DECLARE @idReintentable UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE');
    DECLARE @idEntregada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA');
    DECLARE @idDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');

    DECLARE @ahora DATETIMEOFFSET(7) = SYSUTCDATETIME();
    DECLARE @corr UNIQUEIDENTIFIER;

    -- DB-P01: terminales viejas (> retencion) se borran y eliminadas es exacto
    PRINT '-> DB-P01: depuracion de terminales viejas';
    DECLARE @idViejaEnt UNIQUEIDENTIFIER = NEWID();
    DECLARE @idViejaDef UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, entregadoEn, idCorrelacion)
    VALUES
        (@idViejaEnt, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -40, @ahora), DATEADD(DAY, -40, @ahora), NEWID()),
        (@idViejaDef, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idDefinitiva, 5, DATEADD(DAY, -45, @ahora), NULL, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes
        @retencionDias = 30,
        @lote = 100,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @corr AND eliminadas = 2)
        THROW 53401, 'TEST FAILED DB-P01: no retorno eliminadas = 2 con exito.', 1;

    IF EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id IN (@idViejaEnt, @idViejaDef))
        THROW 53402, 'TEST FAILED DB-P01: las filas terminales viejas no fueron eliminadas.', 1;
    PRINT 'TEST_PASS:DB-P01';
    TRUNCATE TABLE #r;

    -- DB-P02: terminales recientes se conservan
    PRINT '-> DB-P02: terminales recientes se conservan';
    DECLARE @idRecienteEnt UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, entregadoEn, idCorrelacion)
    VALUES (@idRecienteEnt, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -5, @ahora), @ahora, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes
        @retencionDias = 30,
        @lote = 100,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND eliminadas = 0)
        THROW 53403, 'TEST FAILED DB-P02: elimino terminales recientes.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idRecienteEnt)
        THROW 53404, 'TEST FAILED DB-P02: fila reciente no se conservo.', 1;
    PRINT 'TEST_PASS:DB-P02';
    TRUNCATE TABLE #r;

    -- DB-P03: PENDIENTE/RESERVADA/FALLIDA_REINTENTABLE nunca se borran aunque sean viejas
    PRINT '-> DB-P03: no-terminales viejas nunca se borran';
    DECLARE @idViejaPend UNIQUEIDENTIFIER = NEWID();
    DECLARE @idViejaRes UNIQUEIDENTIFIER = NEWID();
    DECLARE @idViejaReint UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, proximoIntentoEn, idCorrelacion)
    VALUES
        (@idViejaPend, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idPendiente, 0, DATEADD(DAY, -50, @ahora), DATEADD(DAY, -50, @ahora), NEWID()),
        (@idViejaRes, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReservada, 1, DATEADD(DAY, -50, @ahora), DATEADD(DAY, -50, @ahora), NEWID()),
        (@idViejaReint, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idReintentable, 2, DATEADD(DAY, -50, @ahora), DATEADD(DAY, -50, @ahora), NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes
        @retencionDias = 30,
        @lote = 100,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idViejaPend)
       OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idViejaRes)
       OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idViejaReint)
        THROW 53405, 'TEST FAILED DB-P03: una notificacion no-terminal fue borrada.', 1;
    PRINT 'TEST_PASS:DB-P03';
    TRUNCATE TABLE #r;

    -- DB-P04: respeta @lote
    PRINT '-> DB-P04: respeta limite de lote';
    DECLARE @idP4_1 UNIQUEIDENTIFIER = NEWID(), @idP4_2 UNIQUEIDENTIFIER = NEWID(), @idP4_3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.NotificacionSaliente (id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, entregadoEn, idCorrelacion)
    VALUES
        (@idP4_1, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -60, @ahora), @ahora, NEWID()),
        (@idP4_2, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -60, @ahora), @ahora, NEWID()),
        (@idP4_3, 'TIPO_TEST', N'A', N'M', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}', @idEntregada, 1, DATEADD(DAY, -60, @ahora), @ahora, NEWID());

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes
        @retencionDias = 30,
        @lote = 2,
        @idCorrelacion = @corr;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND eliminadas = 2)
        THROW 53406, 'TEST FAILED DB-P04: no respeto @lote=2.', 1;
    PRINT 'TEST_PASS:DB-P04';
    TRUNCATE TABLE #r;

    -- DB-P05: retencion 0 o 3651 -> NTF_001
    PRINT '-> DB-P05: retencion fuera de rango';
    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes @retencionDias = 0, @lote = 100, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53407, 'TEST FAILED DB-P05: no rechazo retencionDias 0 con NTF_001.', 1;
    TRUNCATE TABLE #r;

    SET @corr = NEWID();
    INSERT INTO #r EXEC dbo.usp_depurar_notificaciones_salientes @retencionDias = 3651, @lote = 100, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53408, 'TEST FAILED DB-P05: no rechazo retencionDias 3651 con NTF_001.', 1;
    PRINT 'TEST_PASS:DB-P05';

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
    THROW 53499, 'TEST FAILED: test_usp_depurar_notificaciones_salientes dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_depurar_notificaciones_salientes (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_DEPURAR_NOTIFICACIONES_SALIENTES';
GO
