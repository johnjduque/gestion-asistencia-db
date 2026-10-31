USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_registrar_notificacion_saliente (NOTIF-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );
    DECLARE @c UNIQUEIDENTIFIER;
    DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
    DECLARE @userGuid UNIQUEIDENTIFIER = NEWID();
    DECLARE @destValido NVARCHAR(MAX) = CONCAT(N'[{"rol":"ESTUDIANTE","idUsuario":"', CONVERT(NVARCHAR(36), @userGuid), N'"}]');
    DECLARE @traceId CHAR(32) = '4bf92f3577b34da6a3ce929d0e0e4736';
    DECLARE @spanId CHAR(16) = '00f067aa0ba902b7';

    -- DB-N01: Alta valida con 1 destinatario
    PRINT '-> DB-N01: Alta valida con 1 destinatario';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Notificacion de retiro',
        @mensaje = N'Estimado estudiante, ha sido retirado del grupo.',
        @destinatariosJson = @destValido,
        @datosJson = N'{"grupoId":"G1"}',
        @idCorrelacion = @c,
        @traceId = @traceId,
        @spanId = @spanId;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_004|%')
        THROW 53001, 'TEST FAILED DB-N01: no retorno exito con GEN_004.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.NotificacionSaliente
        WHERE idCorrelacion = @c
          AND tipo = 'RETIRO_ESTUDIANTE_GRUPO'
          AND asunto = N'Notificacion de retiro'
          AND idEstado = @idPendiente
          AND intentos = 0
          AND DATEDIFF(MINUTE, creadoEn, SYSUTCDATETIME()) < 5
          AND proximoIntentoEn = creadoEn
          AND reservadoHasta IS NULL
          AND reservadoPor IS NULL
    )
        THROW 53002, 'TEST FAILED DB-N01: fila no persistida en PENDIENTE con campos correctos.', 1;
    PRINT 'TEST_PASS:DB-N01';
    TRUNCATE TABLE #r;

    -- DB-N02: tipo en minuscula con espacios
    PRINT '-> DB-N02: tipo en minuscula con espacios normalizado';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'  retiro_estudiante_grupo  ',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c;

    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 53003, 'TEST FAILED DB-N02: no retorno exito al normalizar tipo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE idCorrelacion = @c AND tipo = 'RETIRO_ESTUDIANTE_GRUPO')
        THROW 53004, 'TEST FAILED DB-N02: tipo no fue normalizado a mayusculas sin espacios.', 1;
    PRINT 'TEST_PASS:DB-N02';
    TRUNCATE TABLE #r;

    -- DB-N03: tipo nulo, vacio, 2 caracteres, 61 caracteres, con simbolos
    PRINT '-> DB-N03: tipo invalido rechazado con NTF_001';
    DECLARE @tiposMalos TABLE (t NVARCHAR(200));
    INSERT INTO @tiposMalos VALUES (NULL), (N''), (N'   '), (N'AB'), (REPLICATE(N'A', 61)), (N'TIPO-INVALIDO!'), (N'TIPO.PUNTO'), (N'TIPO CON ESPACIOS INTERNOS');
    DECLARE @tBad NVARCHAR(200);
    DECLARE curTipos CURSOR LOCAL FOR SELECT t FROM @tiposMalos;
    OPEN curTipos;
    FETCH NEXT FROM curTipos INTO @tBad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @c = NEWID();
        INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
            @tipo = @tBad,
            @asunto = N'Asunto',
            @mensaje = N'Mensaje',
            @destinatariosJson = @destValido,
            @datosJson = N'{}',
            @idCorrelacion = @c;

        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
            THROW 53005, 'TEST FAILED DB-N03: no rechazo tipo invalido con NTF_001.', 1;

        IF EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE idCorrelacion = @c)
            THROW 53006, 'TEST FAILED DB-N03: se inserto fila con tipo invalido.', 1;
        TRUNCATE TABLE #r;
        FETCH NEXT FROM curTipos INTO @tBad;
    END
    CLOSE curTipos;
    DEALLOCATE curTipos;
    PRINT 'TEST_PASS:DB-N03';

    -- DB-N04: destinatariosJson nulo, '[]', no-JSON, objeto en vez de arreglo, 101 elementos, idUsuario no-UUID, rol vacio
    PRINT '-> DB-N04: destinatariosJson invalido rechazado con NTF_001';
    DECLARE @destsMalos TABLE (d NVARCHAR(MAX));
    INSERT INTO @destsMalos VALUES (NULL), (N''), (N'[]'), (N'no es json'), (N'{"rol":"ESTUDIANTE"}'),
        (N'[{"rol":"","idUsuario":"' + CONVERT(NVARCHAR(36), @userGuid) + N'"}]'),
        (N'[{"rol":"ESTUDIANTE","idUsuario":"no-un-uuid"}]'),
        (N'[{"idUsuario":"' + CONVERT(NVARCHAR(36), @userGuid) + N'"}]');
    DECLARE @dBad NVARCHAR(MAX);
    DECLARE curDests CURSOR LOCAL FOR SELECT d FROM @destsMalos;
    OPEN curDests;
    FETCH NEXT FROM curDests INTO @dBad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @c = NEWID();
        INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
            @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
            @asunto = N'Asunto',
            @mensaje = N'Mensaje',
            @destinatariosJson = @dBad,
            @datosJson = N'{}',
            @idCorrelacion = @c;

        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
            THROW 53007, 'TEST FAILED DB-N04: no rechazo destinatariosJson invalido con NTF_001.', 1;
        TRUNCATE TABLE #r;
        FETCH NEXT FROM curDests INTO @dBad;
    END
    CLOSE curDests;
    DEALLOCATE curDests;
    PRINT 'TEST_PASS:DB-N04';

    -- DB-N05: datosJson no-JSON o > 8000 caracteres; nulo -> guarda '{}'
    PRINT '-> DB-N05: datosJson validaciones y default';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'no-es-json',
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53008, 'TEST FAILED DB-N05: no rechazo datosJson no-JSON.', 1;
    TRUNCATE TABLE #r;

    SET @c = NEWID();
    DECLARE @datosLargos NVARCHAR(MAX) = CONCAT(N'{"k":"', REPLICATE(N'x', 8001), N'"}');
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = @datosLargos,
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53009, 'TEST FAILED DB-N05: no rechazo datosJson > 8000.', 1;
    TRUNCATE TABLE #r;

    -- nulo guarda '{}'
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = NULL,
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 53010, 'TEST FAILED DB-N05: no acepto datosJson nulo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE idCorrelacion = @c AND datos = N'{}')
        THROW 53011, 'TEST FAILED DB-N05: datosJson nulo no guardo {}.', 1;
    PRINT 'TEST_PASS:DB-N05';
    TRUNCATE TABLE #r;

    -- DB-N06: asunto de 201 caracteres; mensaje de 4001 caracteres
    PRINT '-> DB-N06: asunto y mensaje fuera de limite';
    SET @c = NEWID();
    DECLARE @asuntoLargo NVARCHAR(400) = REPLICATE(N'A', 201);
    DECLARE @mensajeLargo NVARCHAR(MAX) = REPLICATE(CONVERT(NVARCHAR(MAX), N'M'), 4001);

    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = @asuntoLargo,
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53012, 'TEST FAILED DB-N06: no rechazo asunto > 200.', 1;
    TRUNCATE TABLE #r;

    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = @mensajeLargo,
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_001|%')
        THROW 53013, 'TEST FAILED DB-N06: no rechazo mensaje > 4000.', 1;
    PRINT 'TEST_PASS:DB-N06';
    TRUNCATE TABLE #r;

    -- DB-N07: asunto y mensaje nulos permitidos
    PRINT '-> DB-N07: asunto y mensaje nulos';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = NULL,
        @mensaje = NULL,
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 53014, 'TEST FAILED DB-N07: no acepto asunto y mensaje nulos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE idCorrelacion = @c AND asunto IS NULL AND mensaje IS NULL)
        THROW 53015, 'TEST FAILED DB-N07: columnas asunto y mensaje no quedaron NULL.', 1;
    PRINT 'TEST_PASS:DB-N07';
    TRUNCATE TABLE #r;

    -- DB-N08: @idCorrelacion nulo -> CORR_001
    PRINT '-> DB-N08: idCorrelacion nulo';
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 53016, 'TEST FAILED DB-N08: no rechazo correlacion nula con CORR_001.', 1;
    PRINT 'TEST_PASS:DB-N08';
    TRUNCATE TABLE #r;

    -- DB-N09: traceId y spanId persistidos tal cual
    PRINT '-> DB-N09: traceId y spanId';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c,
        @traceId = @traceId,
        @spanId = @spanId;
    IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE idCorrelacion = @c AND traceId = @traceId AND spanId = @spanId)
        THROW 53017, 'TEST FAILED DB-N09: traceId o spanId no persistidos exactamente.', 1;
    PRINT 'TEST_PASS:DB-N09';
    TRUNCATE TABLE #r;

    -- DB-N10: Estado resuelto desde catalogo (no hardcoded)
    PRINT '-> DB-N10: catalogo resuelto dinamicamente';
    -- Si temporalmente renombramos el codigo de PENDIENTE en el catalogo
    UPDATE dbo.EstadoNotificacion SET codigo = 'PENDIENTE_TMP' WHERE codigo = 'PENDIENTE';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_registrar_notificacion_saliente
        @tipo = N'RETIRO_ESTUDIANTE_GRUPO',
        @asunto = N'Asunto',
        @mensaje = N'Mensaje',
        @destinatariosJson = @destValido,
        @datosJson = N'{}',
        @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0)
        THROW 53018, 'TEST FAILED DB-N10: no fallo de forma controlada al no encontrar PENDIENTE en catalogo.', 1;
    UPDATE dbo.EstadoNotificacion SET codigo = 'PENDIENTE' WHERE codigo = 'PENDIENTE_TMP';
    PRINT 'TEST_PASS:DB-N10';
    TRUNCATE TABLE #r;

    -- DB-N11: El SP no altera el nivel de transaccion del llamador
    IF @@TRANCOUNT <> 1 THROW 53019, 'TEST FAILED DB-N11: el SP altero el @@TRANCOUNT del llamador.', 1;
    PRINT 'TEST_PASS:DB-N11';

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
    THROW 53099, 'TEST FAILED: test_usp_registrar_notificacion_saliente dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_registrar_notificacion_saliente (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_USP_REGISTRAR_NOTIFICACION_SALIENTE';
GO
