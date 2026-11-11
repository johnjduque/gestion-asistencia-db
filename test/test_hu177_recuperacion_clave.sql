USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_hu177_recuperacion_clave (HU177)';
PRINT '==================================================';

-- HU177: enlace de un solo uso para definir una contrasena nueva.
--   HU177_OBJETOS_Y_SEMILLAS     tabla, 4 SP, mensajes RCL_001..003, parametros y plantilla RECUPERACION_CLAVE
--   HU177_SOLICITUD_USUARIO      la solicitud devuelve al usuario activo del correo; nada para correo desconocido, inactivo o vacio
--   HU177_EMISION                la emision guarda solo el hash con vigencia ahora + TTL_MINUTOS
--   HU177_UN_PENDIENTE           pedir otro enlace revoca el anterior; queda un pendiente por usuario
--   HU177_ESPERA_REENVIO         recien emitido un enlace, la solicitud no devuelve fila hasta pasar la espera
--   HU177_EMISION_RECHAZOS       usuario inexistente o inactivo => VCE_007; parametros nulos => estado 0; sin filas nuevas
--   HU177_CONSULTA_NO_CONSUME    la consulta devuelve el usuario y no marca el enlace
--   HU177_CONSUMO_UN_SOLO_USO    el consumo responde RCL_003 una vez; el segundo intento responde RCL_002
--   HU177_ENLACES_INVALIDOS      revocado, vencido, inexistente y de usuario inactivo: la consulta da 0 filas y el consumo RCL_002
--   HU177_PERMISOS               el rol runtime ejecuta los 4 SP y no tiene DML sobre la tabla
BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_solicitud_recuperacion_clave', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_emitir_token_recuperacion_clave', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_token_recuperacion_clave', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consumir_token_recuperacion_clave', N'P') IS NULL
        THROW 57700, 'TEST FAILED HU177_OBJETOS_Y_SEMILLAS: falta la tabla o alguno de los 4 SP.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003') AND estaActivo = 1) <> 3
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003') AND estaActivo = 1) <> 3
        THROW 57701, 'TEST FAILED HU177_OBJETOS_Y_SEMILLAS: faltan los mensajes RCL_001..RCL_003.', 1;
    DECLARE @ttl INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'TTL_MINUTOS');
    DECLARE @espera INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'REENVIO_ESPERA_MINUTOS');
    IF ISNULL(@ttl, 0) <= 0 OR ISNULL(@espera, 0) <= 0
        THROW 57702, 'TEST FAILED HU177_OBJETOS_Y_SEMILLAS: faltan los parametros RECUPERACION_CLAVE.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE' AND idioma = 'es' AND version = 1 AND activa = 1
                                                               AND cuerpo LIKE N'%{enlace}%' AND cuerpo LIKE N'%{nombre}%')
       OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE' AND marcador IN ('nombre', 'enlace') AND obligatorio = 1) <> 2
        THROW 57703, 'TEST FAILED HU177_OBJETOS_Y_SEMILLAS: falta la plantilla RECUPERACION_CLAVE o sus marcadores.', 1;
    PRINT 'TEST_PASS:HU177_OBJETOS_Y_SEMILLAS';

    CREATE TABLE #can (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL,
                       mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NULL);
    CREATE TABLE #sol (idUsuario UNIQUEIDENTIFIER NULL, primerNombre NVARCHAR(50) NULL, correo NVARCHAR(100) NULL);
    CREATE TABLE #dueno (idUsuario UNIQUEIDENTIFIER NULL);

    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @cc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @activo UNIQUEIDENTIFIER = NEWID(), @inactivo UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoActivo NVARCHAR(100) = N'hu177.activo@uco.edu.co', @correoInactivo NVARCHAR(100) = N'hu177.inactivo@uco.edu.co';
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@activo,   @cc, 917700001, N'RECUPERA', N'PRUEBA', N'ACTIVA',   N'', @correoActivo,   1, 1, N'HashBackend_HU177_0001'),
           (@inactivo, @cc, 917700002, N'RECUPERA', N'PRUEBA', N'INACTIVA', N'', @correoInactivo, 1, 0, N'HashBackend_HU177_0002');

    -- Solicitud: solo el usuario activo del correo
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = N'  hu177.activo@uco.edu.co ', @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #sol WHERE idUsuario = @activo AND primerNombre = N'ACTIVA' AND correo = @correoActivo) <> 1 OR (SELECT COUNT(*) FROM #sol) <> 1
        THROW 57710, 'TEST FAILED HU177_SOLICITUD_USUARIO: debio devolver al usuario activo del correo (recortando espacios).', 1;
    DELETE FROM #sol;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = @correoInactivo, @idCorrelacion = @corr;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = N'hu177.nadie@uco.edu.co', @idCorrelacion = @corr;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = N'   ', @idCorrelacion = @corr;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = NULL, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #sol)
        THROW 57711, 'TEST FAILED HU177_SOLICITUD_USUARIO: correo inactivo, desconocido, vacio o nulo no debe devolver filas.', 1;
    PRINT 'TEST_PASS:HU177_SOLICITUD_USUARIO';

    -- Emision
    DECLARE @h1 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'hu177-enlace-1'));
    DECLARE @h2 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'hu177-enlace-2'));
    DECLARE @h3 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'hu177-enlace-3'));
    DECLARE @antes DATETIME2(0) = SYSUTCDATETIME();
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = @activo, @tokenHash = @h1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 1 AND idCorrelacion = @corr) <> 1
        THROW 57720, 'TEST FAILED HU177_EMISION: la emision debio responder estado 1 con la correlacion recibida.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenRecuperacionClave
                   WHERE usuario = @activo AND tokenHash = @h1 AND fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL
                     AND fechaExpiracionUtc BETWEEN DATEADD(MINUTE, @ttl - 2, @antes) AND DATEADD(MINUTE, @ttl + 2, SYSUTCDATETIME()))
        THROW 57721, 'TEST FAILED HU177_EMISION: falta la fila del enlace o su vencimiento no es ahora + TTL_MINUTOS.', 1;
    PRINT 'TEST_PASS:HU177_EMISION';

    -- Espera entre enlaces
    DELETE FROM #sol;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = @correoActivo, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #sol)
        THROW 57730, 'TEST FAILED HU177_ESPERA_REENVIO: recien emitido un enlace no debe devolver fila.', 1;
    UPDATE dbo.TokenRecuperacionClave SET fechaEmisionUtc = DATEADD(MINUTE, -(@espera + 1), fechaEmisionUtc) WHERE tokenHash = @h1;
    INSERT INTO #sol EXEC dbo.usp_consultar_solicitud_recuperacion_clave @correo = @correoActivo, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #sol WHERE idUsuario = @activo) <> 1
        THROW 57731, 'TEST FAILED HU177_ESPERA_REENVIO: pasada la espera debe volver a devolver al usuario.', 1;
    PRINT 'TEST_PASS:HU177_ESPERA_REENVIO';

    -- Un pendiente por usuario
    DELETE FROM #can;
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = @activo, @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenRecuperacionClave WHERE tokenHash = @h1 AND fechaRevocacionUtc IS NOT NULL)
       OR (SELECT COUNT(*) FROM dbo.TokenRecuperacionClave WHERE usuario = @activo AND fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL) <> 1
        THROW 57740, 'TEST FAILED HU177_UN_PENDIENTE: el segundo enlace debe revocar el primero y quedar como unico pendiente.', 1;
    PRINT 'TEST_PASS:HU177_UN_PENDIENTE';

    -- Rechazos de la emision
    DECLARE @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_007', @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    DELETE FROM #can;
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = @inactivo, @tokenHash = @h3, @idCorrelacion = @corr;
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = '99999999-9999-9999-9999-999999999999', @tokenHash = @h3, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 2
        THROW 57750, 'TEST FAILED HU177_EMISION_RECHAZOS: usuario inactivo o inexistente debe responder VCE_007 con estado 0.', 1;
    DELETE FROM #can;
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = NULL, @tokenHash = @h3, @idCorrelacion = @corr;
    INSERT INTO #can EXEC dbo.usp_emitir_token_recuperacion_clave @idUsuario = @activo, @tokenHash = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 0) <> 2 OR EXISTS (SELECT 1 FROM dbo.TokenRecuperacionClave WHERE tokenHash = @h3)
        THROW 57751, 'TEST FAILED HU177_EMISION_RECHAZOS: parametros nulos deben responder estado 0 sin crear filas.', 1;
    PRINT 'TEST_PASS:HU177_EMISION_RECHAZOS';

    -- Consulta sin consumir
    INSERT INTO #dueno EXEC dbo.usp_consultar_token_recuperacion_clave @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #dueno WHERE idUsuario = @activo) <> 1
       OR EXISTS (SELECT 1 FROM dbo.TokenRecuperacionClave WHERE tokenHash = @h2 AND (fechaUsoUtc IS NOT NULL OR fechaRevocacionUtc IS NOT NULL))
        THROW 57760, 'TEST FAILED HU177_CONSULTA_NO_CONSUME: la consulta debe devolver el usuario y dejar el enlace intacto.', 1;
    PRINT 'TEST_PASS:HU177_CONSULTA_NO_CONSUME';

    -- Consumo de un solo uso
    DECLARE @ok NVARCHAR(4000), @invalido NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCL_003', @mensajeUsuarioResultado = @ok OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCL_002', @mensajeUsuarioResultado = @invalido OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    DELETE FROM #can;
    INSERT INTO #can EXEC dbo.usp_consumir_token_recuperacion_clave @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @ok) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.TokenRecuperacionClave WHERE tokenHash = @h2 AND fechaUsoUtc IS NOT NULL)
        THROW 57770, 'TEST FAILED HU177_CONSUMO_UN_SOLO_USO: el primer consumo debe responder RCL_003 y marcar el uso.', 1;
    DELETE FROM #can;
    INSERT INTO #can EXEC dbo.usp_consumir_token_recuperacion_clave @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @invalido) <> 1
        THROW 57771, 'TEST FAILED HU177_CONSUMO_UN_SOLO_USO: el segundo consumo debe responder RCL_002.', 1;
    PRINT 'TEST_PASS:HU177_CONSUMO_UN_SOLO_USO';

    -- Enlaces que no sirven: revocado (@h1), usado (@h2), inexistente (@h3), vencido y de usuario inactivo
    DECLARE @vencido VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'hu177-enlace-vencido'));
    DECLARE @deInactivo VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'hu177-enlace-inactivo'));
    INSERT INTO dbo.TokenRecuperacionClave (usuario, tokenHash, fechaEmisionUtc, fechaExpiracionUtc)
    VALUES (@activo,   @vencido,    DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME())),
           (@inactivo, @deInactivo, SYSUTCDATETIME(),                    DATEADD(HOUR, 1, SYSUTCDATETIME()));
    DELETE FROM #dueno;
    DELETE FROM #can;
    DECLARE @malos TABLE (h VARBINARY(32) NULL);
    INSERT @malos VALUES (@h1), (@h2), (@h3), (@vencido), (@deInactivo), (NULL);
    DECLARE @h VARBINARY(32);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT h FROM @malos;
    OPEN c;
    FETCH NEXT FROM c INTO @h;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #dueno EXEC dbo.usp_consultar_token_recuperacion_clave @tokenHash = @h, @idCorrelacion = @corr;
        INSERT INTO #can EXEC dbo.usp_consumir_token_recuperacion_clave @tokenHash = @h, @idCorrelacion = @corr;
        FETCH NEXT FROM c INTO @h;
    END
    CLOSE c;
    DEALLOCATE c;
    IF EXISTS (SELECT 1 FROM #dueno)
        THROW 57780, 'TEST FAILED HU177_ENLACES_INVALIDOS: un enlace que no sirve no debe devolver usuario.', 1;
    IF (SELECT COUNT(*) FROM #can WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @invalido) <> 6
        THROW 57781, 'TEST FAILED HU177_ENLACES_INVALIDOS: todo enlace que no sirve debe responder RCL_002 por igual.', 1;
    PRINT 'TEST_PASS:HU177_ENLACES_INVALIDOS';

    -- Permisos
    IF (SELECT COUNT(*) FROM sys.database_permissions p
        WHERE p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND p.permission_name = 'EXECUTE' AND p.state IN ('G', 'W')
          AND p.major_id IN (OBJECT_ID(N'dbo.usp_consultar_solicitud_recuperacion_clave'), OBJECT_ID(N'dbo.usp_emitir_token_recuperacion_clave'),
                             OBJECT_ID(N'dbo.usp_consultar_token_recuperacion_clave'), OBJECT_ID(N'dbo.usp_consumir_token_recuperacion_clave'))) <> 4
        THROW 57790, 'TEST FAILED HU177_PERMISOS: el rol runtime debe tener EXECUTE sobre los 4 SP de HU177.', 1;
    IF EXISTS (SELECT 1 FROM sys.database_permissions p
               WHERE p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND p.major_id = OBJECT_ID(N'dbo.TokenRecuperacionClave')
                 AND p.state IN ('G', 'W'))
        THROW 57791, 'TEST FAILED HU177_PERMISOS: el rol runtime no debe tener permisos directos sobre dbo.TokenRecuperacionClave.', 1;
    PRINT 'TEST_PASS:HU177_PERMISOS';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 57799, 'TEST FAILED HU177_TRANCOUNT_ZERO: test_hu177_recuperacion_clave dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:HU177_TRANCOUNT_ZERO';
PRINT 'TEST PASS: test_hu177_recuperacion_clave (OK)';
GO
