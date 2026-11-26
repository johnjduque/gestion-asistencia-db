USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 8 (plan por lotes 2026-11-25): notificaciones.
-- Fija el comportamiento de los internos del lote antes de refactorizarlos (no tenian prueba directa). Los SP publicos del lote
-- siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL8_R01_REGISTRAR_SALIENTE   usp_registrar_notificacion_saliente_interno: GEN_004 y fila PENDIENTE con intentos 0
--   SKL8_R02_RESERVAR             usp_reservar_notificaciones_salientes_interno: reserva la mas antigua, suma un intento y
--                                 devuelve las 11 columnas
--   SKL8_R03_MARCAR_ENTREGADA     usp_marcar_notificacion_entregada_interno: GEN_005, ENTREGADA y limpia reserva y error
--   SKL8_R04_FALLO                usp_registrar_fallo_notificacion_interno: reintentable con backoff (tope max) y definitiva
--   SKL8_R05_DEPURAR              usp_depurar_notificaciones_salientes_interno: borra solo terminales vencidas, respeta el lote
--   SKL8_R06_CORREO_PERSONAL      usp_validar_correo_institucional_personal_interno: vacio pasa, dominio institucional pasa,
--                                 otro dominio VCE_008
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote8_caracterizacion';

DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
DECLARE @idReservada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA');
DECLARE @idReintentable UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_REINTENTABLE');
DECLARE @idEntregada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'ENTREGADA');
DECLARE @idDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');
IF @idPendiente IS NULL OR @idReservada IS NULL OR @idReintentable IS NULL OR @idEntregada IS NULL OR @idDefinitiva IS NULL
    THROW 55800, 'TEST FAILED: SKL8 faltan estados de notificacion del seed.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @id UNIQUEIDENTIFIER, @n INT, @eliminadas INT;
    DECLARE @intentos INT, @prox DATETIMEOFFSET(7), @estado UNIQUEIDENTIFIER, @creado DATETIMEOFFSET(7);
    DECLARE @dom NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');

    -- ================================================================= R01
    EXEC dbo.usp_registrar_notificacion_saliente_interno
         @tipo = 'SKL8_TIPO', @asunto = N'asunto skl8', @mensaje = N'mensaje skl8',
         @destinatariosJson = N'["11111111-1111-1111-1111-111111111111"]', @datosJson = N'{"k":1}',
         @idEstadoPendiente = @idPendiente, @traceId = '0123456789abcdef0123456789abcdef', @spanId = '0123456789abcdef',
         @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    SELECT @id = id, @intentos = intentos, @prox = proximoIntentoEn, @creado = creadoEn, @estado = idEstado
    FROM dbo.NotificacionSaliente WHERE tipo = 'SKL8_TIPO' AND idCorrelacion = @corr;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
       OR @id IS NULL OR @intentos <> 0 OR @prox <> @creado OR @estado <> @idPendiente
        THROW 55810, 'TEST FAILED: SKL8_R01_REGISTRAR_SALIENTE', 1;
    PRINT 'TEST_PASS:SKL8_R01_REGISTRAR_SALIENTE';

    -- ================================================================= R02
    UPDATE dbo.NotificacionSaliente SET creadoEn = '2000-01-01T00:00:00+00:00', proximoIntentoEn = '2000-01-01T00:00:00+00:00' WHERE id = @id;
    CREATE TABLE #res (id UNIQUEIDENTIFIER, tipo VARCHAR(60), asunto NVARCHAR(200), mensaje NVARCHAR(4000), destinatarios NVARCHAR(MAX),
        datos NVARCHAR(MAX), intentos INT, creadoEn DATETIMEOFFSET(7), idCorrelacion UNIQUEIDENTIFIER, traceId CHAR(32), spanId CHAR(16));
    INSERT INTO #res EXEC dbo.usp_reservar_notificaciones_salientes_interno @lote = 1, @leaseSegundos = 60, @instancia = N'skl8-worker', @idCorrelacion = @corr;
    SELECT @n = COUNT(*) FROM #res WHERE id = @id AND intentos = 1 AND tipo = 'SKL8_TIPO' AND datos = N'{"k":1}' AND idCorrelacion = @corr
        AND traceId = '0123456789abcdef0123456789abcdef' AND spanId = '0123456789abcdef';
    IF @n <> 1 OR (SELECT COUNT(*) FROM #res) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id AND idEstado = @idReservada AND reservadoPor = N'skl8-worker'
                      AND reservadoHasta > SYSUTCDATETIME() AND intentos = 1)
        THROW 55820, 'TEST FAILED: SKL8_R02_RESERVAR', 1;
    PRINT 'TEST_PASS:SKL8_R02_RESERVAR';

    -- ================================================================= R03
    UPDATE dbo.NotificacionSaliente SET codigoError = 'X', detalleError = N'x' WHERE id = @id;
    EXEC dbo.usp_marcar_notificacion_entregada_interno @id = @id, @idEstadoEntregada = @idEntregada, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
       OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id AND idEstado = @idEntregada AND entregadoEn IS NOT NULL
                      AND reservadoHasta IS NULL AND reservadoPor IS NULL AND codigoError IS NULL AND detalleError IS NULL)
        THROW 55830, 'TEST FAILED: SKL8_R03_MARCAR_ENTREGADA', 1;
    PRINT 'TEST_PASS:SKL8_R03_MARCAR_ENTREGADA';

    -- ================================================================= R04
    -- reintentable: intentos 3 -> base 10 * 2^2 = 40 s
    UPDATE dbo.NotificacionSaliente SET idEstado = @idReservada, intentos = 3, reservadoPor = N'w', reservadoHasta = SYSUTCDATETIME() WHERE id = @id;
    EXEC dbo.usp_registrar_fallo_notificacion_interno @id = @id, @codigoError = 'SMTP_TMP', @detalleError = N'temporal', @reintentable = 1,
         @maxIntentos = 5, @backoffBaseSegundos = 10, @backoffMaxSegundos = 3600, @idEstadoReintentable = @idReintentable,
         @idEstadoDefinitiva = @idDefinitiva, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    SELECT @prox = proximoIntentoEn, @estado = idEstado FROM dbo.NotificacionSaliente WHERE id = @id;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%' OR @estado <> @idReintentable
       OR DATEDIFF(SECOND, SYSUTCDATETIME(), @prox) NOT BETWEEN 35 AND 41
       OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id AND codigoError = 'SMTP_TMP' AND detalleError = N'temporal'
                      AND reservadoPor IS NULL AND reservadoHasta IS NULL)
        THROW 55840, 'TEST FAILED: SKL8_R04_FALLO (reintentable)', 1;
    -- tope: intentos 20 con max 100 -> backoffMax 50
    UPDATE dbo.NotificacionSaliente SET intentos = 20 WHERE id = @id;
    EXEC dbo.usp_registrar_fallo_notificacion_interno @id = @id, @codigoError = 'SMTP_TMP', @detalleError = N'temporal', @reintentable = 1,
         @maxIntentos = 100, @backoffBaseSegundos = 10, @backoffMaxSegundos = 50, @idEstadoReintentable = @idReintentable,
         @idEstadoDefinitiva = @idDefinitiva, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    SELECT @prox = proximoIntentoEn FROM dbo.NotificacionSaliente WHERE id = @id;
    IF @ok <> 1 OR DATEDIFF(SECOND, SYSUTCDATETIME(), @prox) NOT BETWEEN 45 AND 51
        THROW 55841, 'TEST FAILED: SKL8_R04_FALLO (tope backoff)', 1;
    -- intentos agotados -> definitiva sin proximo intento
    UPDATE dbo.NotificacionSaliente SET intentos = 5 WHERE id = @id;
    EXEC dbo.usp_registrar_fallo_notificacion_interno @id = @id, @codigoError = 'SMTP_TMP', @detalleError = N'agotado', @reintentable = 1,
         @maxIntentos = 5, @backoffBaseSegundos = 10, @backoffMaxSegundos = 3600, @idEstadoReintentable = @idReintentable,
         @idEstadoDefinitiva = @idDefinitiva, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id AND idEstado = @idDefinitiva AND proximoIntentoEn IS NULL AND detalleError = N'agotado')
        THROW 55842, 'TEST FAILED: SKL8_R04_FALLO (definitiva por intentos)', 1;
    -- no reintentable -> definitiva
    UPDATE dbo.NotificacionSaliente SET intentos = 1, idEstado = @idReservada WHERE id = @id;
    EXEC dbo.usp_registrar_fallo_notificacion_interno @id = @id, @codigoError = 'SMTP_550', @detalleError = N'rechazo', @reintentable = 0,
         @maxIntentos = 5, @backoffBaseSegundos = 10, @backoffMaxSegundos = 3600, @idEstadoReintentable = @idReintentable,
         @idEstadoDefinitiva = @idDefinitiva, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @id AND idEstado = @idDefinitiva AND proximoIntentoEn IS NULL AND codigoError = 'SMTP_550')
        THROW 55843, 'TEST FAILED: SKL8_R04_FALLO (no reintentable)', 1;
    PRINT 'TEST_PASS:SKL8_R04_FALLO';

    -- ================================================================= R05
    -- 3 terminales vencidas (la de R01 definitiva + 2 nuevas), 1 terminal reciente y 1 pendiente vencida; lote 2 borra las 2 mas antiguas
    DECLARE @v1 UNIQUEIDENTIFIER = NEWID(), @v2 UNIQUEIDENTIFIER = NEWID(), @rec UNIQUEIDENTIFIER = NEWID(), @pen UNIQUEIDENTIFIER = NEWID();
    UPDATE dbo.NotificacionSaliente SET creadoEn = '2000-01-03T00:00:00+00:00' WHERE id = @id;
    INSERT INTO dbo.NotificacionSaliente (id, tipo, destinatarios, idEstado, creadoEn) VALUES
        (@v1, 'SKL8_TIPO', N'[]', @idEntregada,  '2000-01-01T00:00:00+00:00'),
        (@v2, 'SKL8_TIPO', N'[]', @idDefinitiva, '2000-01-02T00:00:00+00:00'),
        (@rec, 'SKL8_TIPO', N'[]', @idEntregada, SYSUTCDATETIME()),
        (@pen, 'SKL8_TIPO', N'[]', @idPendiente, '1999-01-01T00:00:00+00:00');
    EXEC dbo.usp_depurar_notificaciones_salientes_interno @retencionDias = 30, @lote = 2, @idEstadoEntregada = @idEntregada,
         @idEstadoDefinitiva = @idDefinitiva, @idCorrelacion = @corr, @eliminadas = @eliminadas OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @eliminadas <> 2 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%' OR @mt NOT LIKE N'% Eliminadas: 2. Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
       OR EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id IN (@v1, @v2))
       OR (SELECT COUNT(*) FROM dbo.NotificacionSaliente WHERE id IN (@id, @rec, @pen)) <> 3
        THROW 55850, 'TEST FAILED: SKL8_R05_DEPURAR', 1;
    PRINT 'TEST_PASS:SKL8_R05_DEPURAR';

    -- ================================================================= R06
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = N'  ', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55860, 'TEST FAILED: SKL8_R06_CORREO_PERSONAL (vacio)', 1;
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55861, 'TEST FAILED: SKL8_R06_CORREO_PERSONAL (nulo)', 1;
    DECLARE @inst NVARCHAR(255) = N'skl8.prueba' + IIF(LEFT(@dom, 1) = N'@', @dom, N'@' + @dom);
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = @inst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55862, 'TEST FAILED: SKL8_R06_CORREO_PERSONAL (institucional)', 1;
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = N'skl8.prueba@gmail.com', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VCE[_]008|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55863, 'TEST FAILED: SKL8_R06_CORREO_PERSONAL (VCE_008)', 1;
    PRINT 'TEST_PASS:SKL8_R06_CORREO_PERSONAL';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST END: test_skills_lote8_caracterizacion';
GO
