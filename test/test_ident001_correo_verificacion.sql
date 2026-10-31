USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_ident001_correo_verificacion (IDENT-001)';
PRINT '==================================================';

BEGIN TRANSACTION;
BEGIN TRY
    -- =========================================================================
    -- 0. Existencia de los objetos del contrato (falla en RED si faltan)
    -- =========================================================================
    IF OBJECT_ID(N'dbo.TokenVerificacionCorreo', N'U') IS NULL
        THROW 55000, 'TEST FAILED DB-T00: tabla dbo.TokenVerificacionCorreo no existe.', 1;
    IF OBJECT_ID(N'dbo.ufn_correo_cumple_dominio_institucional', N'FN') IS NULL
        THROW 55001, 'TEST FAILED DB-D00: funcion dbo.ufn_correo_cumple_dominio_institucional no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_emitir_token_verificacion_correo', N'P') IS NULL
        THROW 55002, 'TEST FAILED DB-T00: SP usp_emitir_token_verificacion_correo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_consultar_token_verificacion_correo', N'P') IS NULL
        THROW 55003, 'TEST FAILED DB-V00: SP usp_consultar_token_verificacion_correo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_confirmar_verificacion_correo', N'P') IS NULL
        THROW 55004, 'TEST FAILED DB-C00: SP usp_confirmar_verificacion_correo no existe.', 1;
    IF OBJECT_ID(N'dbo.usp_consultar_reenvio_verificacion_correo', N'P') IS NULL
        THROW 55005, 'TEST FAILED DB-R00: SP usp_consultar_reenvio_verificacion_correo no existe.', 1;

    -- =========================================================================
    -- Fixtures
    -- =========================================================================
    CREATE TABLE #r (
        idCorrelacion UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(MAX) NULL,
        mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL
    );

    DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @grupo UNIQUEIDENTIFIER, @docenteTitular UNIQUEIDENTIFIER, @userTitular UNIQUEIDENTIFIER;
    DECLARE @userOtroDocente UNIQUEIDENTIFIER, @userCoordPrograma UNIQUEIDENTIFIER;

    SELECT TOP 1 @grupo = g.id, @docenteTitular = g.docente
    FROM dbo.Grupo g
    INNER JOIN dbo.uv_grupo vg ON vg.id = g.id
    WHERE vg.grupoEstaHablitado = 1 AND vg.cuposDisponibles > 5
    ORDER BY vg.cuposDisponibles DESC;

    SELECT @userTitular = usuario FROM dbo.Docente WHERE id = @docenteTitular;
    SELECT TOP 1 @userOtroDocente = usuario FROM dbo.Docente WHERE id <> @docenteTitular AND usuario <> @userTitular ORDER BY id;
    SELECT @userCoordPrograma = c.usuario
    FROM dbo.Grupo g
    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    INNER JOIN dbo.Programa pr ON pr.id = pe.programa
    INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
    WHERE g.id = @grupo;

    IF @dominio IS NULL OR @dominio = N'' OR @tipoCC IS NULL OR @grupo IS NULL OR @userTitular IS NULL
       OR @userOtroDocente IS NULL OR @userCoordPrograma IS NULL
        THROW 55010, 'TEST FAILED IDENT-001: fixture o parametro REGISTRO/DOMINIO_CORREO_ESTUDIANTE faltante (semilla).', 1;

    -- =========================================================================
    -- DB-D01: ufn_correo_cumple_dominio_institucional
    -- =========================================================================
    PRINT '-> DB-D01: funcion de dominio institucional';
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'a@uco.edu.co',             N'@uco.edu.co', 1),
            (N'A@UCO.EDU.CO ',            N'@uco.edu.co', 1),
            (N'  maria.perez@uco.edu.co', N'@uco.edu.co', 1),
            (N'a@a.uco.edu.co',           N'@uco.edu.co', 0),
            (N'a@uco.edu.co.evil.com',    N'@uco.edu.co', 0),
            (N'@uco.edu.co',              N'@uco.edu.co', 0),
            (N'a@@uco.edu.co',            N'@uco.edu.co', 0),
            (N'a@uco.edu.co@x.com',       N'@uco.edu.co', 0),
            (N'a@gmail.com',              N'@uco.edu.co', 0),
            (N'auco.edu.co',              N'@uco.edu.co', 0),
            (NULL,                        N'@uco.edu.co', 0),
            (N'a@uco.edu.co',             N'',            0),
            (N'a@uco.edu.co',             NULL,           0),
            (N'a@uco.edu.co',             N'uco.edu.co',  0),
            (N'a@otra.edu',               N'@otra.edu',   1)
        ) AS c(correo, dominio, esperado)
        WHERE dbo.ufn_correo_cumple_dominio_institucional(c.correo, c.dominio) <> c.esperado
    )
        THROW 55020, 'TEST FAILED DB-D01: la funcion de dominio devolvio un resultado inesperado.', 1;
    PRINT 'TEST_PASS:DB-D01';

    -- =========================================================================
    -- DB-D02 / DB-D05: registro manual con correo no institucional / institucional
    -- =========================================================================
    PRINT '-> DB-D02: correo no institucional se rechaza sin escrituras (VCE_001)';
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @numero INT = 1100000000 + ABS(CHECKSUM(NEWID()) % 400000000);
    DECLARE @correoMalo NVARCHAR(255) = CONCAT(N'ident001.malo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@gmail.com');
    DECLARE @usrAntes INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @estAntes INT = (SELECT COUNT(*) FROM dbo.Estudiante);
    DECLARE @egAntes INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    DECLARE @msgU NVARCHAR(4000), @msgT NVARCHAR(4000);

    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @numero,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Uno', @segundoApellido = N'Prueba',
        @correo = @correoMalo, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_001', @p_param1 = @dominio,
        @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @corr AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 55030, 'TEST FAILED DB-D02: no devolvio estado 0 con el mensaje VCE_001 del catalogo.', 1;
    IF @msgU NOT LIKE CONCAT(N'%', @dominio, N'%')
        THROW 55031, 'TEST FAILED DB-D02: el mensaje VCE_001 no incluye el dominio configurado.', 1;
    IF @usrAntes <> (SELECT COUNT(*) FROM dbo.Usuario)
       OR @estAntes <> (SELECT COUNT(*) FROM dbo.Estudiante)
       OR @egAntes <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo)
        THROW 55032, 'TEST FAILED DB-D02: el rechazo dejo escrituras en Usuario/Estudiante/EstudianteGrupo.', 1;
    PRINT 'TEST_PASS:DB-D02';

    PRINT '-> DB-D05: correo institucional se registra con correoConfirmado = 0';
    DECLARE @correoBueno NVARCHAR(255) = CONCAT(N'ident001.bueno.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio);
    DECLARE @corr2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @numero2 INT = @numero + 1;
    DECLARE @n_2 INT = @numero + 2, @n_3 INT = @numero + 3, @n_4 INT = @numero + 4, @n_30 INT = @numero + 30;
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @numero2,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Dos', @segundoApellido = N'Prueba',
        @correo = @correoBueno, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr2, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 55033, 'TEST FAILED DB-D05: el registro institucional debio ser exitoso.', 1;
    DECLARE @usuarioNuevo UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = LOWER(@correoBueno));
    IF @usuarioNuevo IS NULL
        THROW 55034, 'TEST FAILED DB-D05: no se creo el usuario.', 1;
    IF (SELECT correoConfirmado FROM dbo.Usuario WHERE id = @usuarioNuevo) <> 0
        THROW 55035, 'TEST FAILED DB-D05: correoConfirmado debia ser 0 en un alta nueva.', 1;
    PRINT 'TEST_PASS:DB-D05';

    -- =========================================================================
    -- DB-D03: el dominio es un parametro (cambiarlo cambia la validacion)
    -- =========================================================================
    PRINT '-> DB-D03: el dominio se lee del parametro';
    UPDATE dbo.CatalogoParametro SET valor = N'@otra.edu' WHERE grupo = 'REGISTRO' AND clave = 'DOMINIO_CORREO_ESTUDIANTE';
    DECLARE @corr3 UNIQUEIDENTIFIER = NEWID();
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @n_2,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Tres', @segundoApellido = N'Prueba',
        @correo = @correoBueno, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr3, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    -- Con @otra.edu, un correo @uco.edu.co de un documento distinto ya existente por correo se resuelve como usuario existente (D5),
    -- por eso se prueba con un correo nuevo del dominio anterior:
    DECLARE @correoViejoDominio NVARCHAR(255) = CONCAT(N'ident001.viejo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio);
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @n_3,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Cuatro', @segundoApellido = N'Prueba',
        @correo = @correoViejoDominio, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr3, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0) <> 1
        THROW 55036, 'TEST FAILED DB-D03: con dominio @otra.edu un correo del dominio anterior debio rechazarse.', 1;
    DECLARE @correoNuevoDominio NVARCHAR(255) = CONCAT(N'ident001.nuevo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@otra.edu');
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @n_4,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Cinco', @segundoApellido = N'Prueba',
        @correo = @correoNuevoDominio, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr3, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 55037, 'TEST FAILED DB-D03: con dominio @otra.edu un correo @otra.edu debio aceptarse.', 1;
    UPDATE dbo.CatalogoParametro SET valor = @dominio WHERE grupo = 'REGISTRO' AND clave = 'DOMINIO_CORREO_ESTUDIANTE';
    PRINT 'TEST_PASS:DB-D03';

    -- =========================================================================
    -- DB-D04: un usuario existente (mismo correo y documento) no se revalida (D5)
    -- =========================================================================
    PRINT '-> DB-D04: usuario existente con otro dominio no se revalida';
    DECLARE @correoExistente NVARCHAR(255) = CONCAT(N'ident001.existente.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@gmail.com');
    DECLARE @numeroExistente INT = @numero + 10;
    DECLARE @idUsuarioExistente UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@idUsuarioExistente, @tipoCC, @numeroExistente, N'EXISTENTE', N'PRUEBA', N'IDENT', N'CERO', LOWER(@correoExistente), 1, 1, N'HashBackend_Ident001_1234567890');
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @numeroExistente,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Existente', @segundoApellido = N'Prueba',
        @correo = @correoExistente, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr3, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 55038, 'TEST FAILED DB-D04: un usuario existente no debia revalidar el dominio.', 1;
    PRINT 'TEST_PASS:DB-D04';

    -- =========================================================================
    -- DB-T01..T03: emision de token
    -- =========================================================================
    PRINT '-> DB-T01: emision de token (solo el hash)';
    DECLARE @h1 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-token-1'));
    DECLARE @h2 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-token-2'));
    DECLARE @ttlHoras INT = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'TTL_HORAS');
    IF @ttlHoras IS NULL OR @ttlHoras <= 0
        THROW 55040, 'TEST FAILED DB-T01: parametro VERIFICACION_CORREO/TTL_HORAS ausente.', 1;
    DECLARE @ahora DATETIME2(0) = SYSUTCDATETIME();
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_emitir_token_verificacion_correo @idUsuario = @usuarioNuevo, @tokenHash = @h1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 55041, 'TEST FAILED DB-T01: la emision debio ser exitosa.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.TokenVerificacionCorreo
        WHERE usuario = @usuarioNuevo AND tokenHash = @h1 AND fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL
          AND fechaExpiracionUtc BETWEEN DATEADD(HOUR, @ttlHoras, DATEADD(MINUTE, -2, @ahora)) AND DATEADD(HOUR, @ttlHoras, DATEADD(MINUTE, 2, SYSUTCDATETIME()))
    )
        THROW 55042, 'TEST FAILED DB-T01: fila del token ausente o con expiracion distinta a ahora + TTL.', 1;
    PRINT 'TEST_PASS:DB-T01';

    PRINT '-> DB-T02: un solo token activo por usuario';
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_emitir_token_verificacion_correo @idUsuario = @usuarioNuevo, @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 1
        THROW 55043, 'TEST FAILED DB-T02: la segunda emision debio ser exitosa.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenVerificacionCorreo WHERE tokenHash = @h1 AND fechaRevocacionUtc IS NOT NULL)
        THROW 55044, 'TEST FAILED DB-T02: el token anterior debio quedar revocado.', 1;
    IF (SELECT COUNT(*) FROM dbo.TokenVerificacionCorreo WHERE usuario = @usuarioNuevo AND fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL) <> 1
        THROW 55045, 'TEST FAILED DB-T02: debe existir exactamente un token activo por usuario.', 1;
    PRINT 'TEST_PASS:DB-T02';

    PRINT '-> DB-T03: no se emite token para un correo ya verificado (VCE_005)';
    DECLARE @h3 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-token-3'));
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_emitir_token_verificacion_correo @idUsuario = @idUsuarioExistente, @tokenHash = @h3, @idCorrelacion = @corr;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_005', @mensajeUsuarioResultado = @msgU OUTPUT, @mensajeTecnicoResultado = @msgT OUTPUT;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgU) <> 1
        THROW 55046, 'TEST FAILED DB-T03: debio responder VCE_005 con estado 0.', 1;
    IF EXISTS (SELECT 1 FROM dbo.TokenVerificacionCorreo WHERE usuario = @idUsuarioExistente)
        THROW 55047, 'TEST FAILED DB-T03: no debio crear ninguna fila para un correo verificado.', 1;
    PRINT 'TEST_PASS:DB-T03';

    -- =========================================================================
    -- DB-V01 / DB-V02: consulta del token (no consume; uniforme ante invalidos)
    -- =========================================================================
    PRINT '-> DB-V01: consulta de un token vigente devuelve el usuario y no lo consume';
    CREATE TABLE #tok (idUsuario UNIQUEIDENTIFIER NULL);
    INSERT INTO #tok EXEC dbo.usp_consultar_token_verificacion_correo @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #tok WHERE idUsuario = @usuarioNuevo) <> 1
        THROW 55050, 'TEST FAILED DB-V01: debio devolver exactamente el usuario del token.', 1;
    IF EXISTS (SELECT 1 FROM dbo.TokenVerificacionCorreo WHERE tokenHash = @h2 AND (fechaUsoUtc IS NOT NULL OR fechaRevocacionUtc IS NOT NULL))
        THROW 55051, 'TEST FAILED DB-V01: la consulta no debe consumir el token.', 1;
    PRINT 'TEST_PASS:DB-V01';

    PRINT '-> DB-V02: tokens invalidos son indistinguibles (0 filas)';
    DECLARE @hVencido VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-vencido'));
    DECLARE @hUsado VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-usado'));
    DECLARE @hInexistente VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-no-existe'));
    DECLARE @hInactivo VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-inactivo'));
    DECLARE @idUsuarioInactivo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@idUsuarioInactivo, @tipoCC, @numero + 20, N'INACTIVO', N'PRUEBA', N'IDENT', N'CERO', LOWER(CONCAT(N'ident001.inactivo.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio)), 0, 0, N'HashBackend_Ident001_1234567890');
    INSERT INTO dbo.TokenVerificacionCorreo (id, usuario, tokenHash, fechaEmisionUtc, fechaExpiracionUtc, fechaUsoUtc, fechaRevocacionUtc)
    VALUES (NEWID(), @usuarioNuevo, @hVencido, DATEADD(HOUR, -30, SYSUTCDATETIME()), DATEADD(HOUR, -6, SYSUTCDATETIME()), NULL, SYSUTCDATETIME()),
           (NEWID(), @usuarioNuevo, @hUsado, DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, 21, SYSUTCDATETIME()), SYSUTCDATETIME(), NULL),
           (NEWID(), @idUsuarioInactivo, @hInactivo, SYSUTCDATETIME(), DATEADD(HOUR, 24, SYSUTCDATETIME()), NULL, NULL);
    DECLARE @invalidos INT = 0;
    DECLARE @hashes TABLE (h VARBINARY(32));
    INSERT INTO @hashes VALUES (@hVencido), (@hUsado), (@hInexistente), (@hInactivo), (NULL);
    DECLARE @hh VARBINARY(32);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT h FROM @hashes;
    OPEN cur;
    FETCH NEXT FROM cur INTO @hh;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM #tok;
        INSERT INTO #tok EXEC dbo.usp_consultar_token_verificacion_correo @tokenHash = @hh, @idCorrelacion = @corr;
        SET @invalidos += (SELECT COUNT(*) FROM #tok);
        FETCH NEXT FROM cur INTO @hh;
    END
    CLOSE cur; DEALLOCATE cur;
    IF @invalidos <> 0
        THROW 55052, 'TEST FAILED DB-V02: un token vencido/usado/inexistente/de usuario inactivo/nulo debio devolver 0 filas.', 1;
    PRINT 'TEST_PASS:DB-V02';

    -- =========================================================================
    -- DB-C01 / DB-C02: confirmacion (consume y marca correoConfirmado)
    -- =========================================================================
    PRINT '-> DB-C01: la confirmacion consume el token y marca correoConfirmado = 1';
    DECLARE @msgOk NVARCHAR(4000), @msgOkT NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_006', @mensajeUsuarioResultado = @msgOk OUTPUT, @mensajeTecnicoResultado = @msgOkT OUTPUT;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_confirmar_verificacion_correo @tokenHash = @h2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @msgOk) <> 1
        THROW 55060, 'TEST FAILED DB-C01: debio responder exito con el mensaje VCE_006.', 1;
    IF (SELECT correoConfirmado FROM dbo.Usuario WHERE id = @usuarioNuevo) <> 1
        THROW 55061, 'TEST FAILED DB-C01: correoConfirmado debia quedar en 1.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.TokenVerificacionCorreo WHERE tokenHash = @h2 AND fechaUsoUtc IS NOT NULL)
        THROW 55062, 'TEST FAILED DB-C01: el token debia quedar con fechaUsoUtc.', 1;
    PRINT 'TEST_PASS:DB-C01';

    PRINT '-> DB-C02: un token usado, vencido o inexistente se rechaza con VCE_002';
    DECLARE @msgInv NVARCHAR(4000), @msgInvT NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VCE_002', @mensajeUsuarioResultado = @msgInv OUTPUT, @mensajeTecnicoResultado = @msgInvT OUTPUT;
    DECLARE @malos INT = 0;
    DELETE FROM @hashes;
    INSERT INTO @hashes VALUES (@h2), (@hVencido), (@hUsado), (@hInexistente), (@hInactivo);
    DECLARE cur2 CURSOR LOCAL FAST_FORWARD FOR SELECT h FROM @hashes;
    OPEN cur2;
    FETCH NEXT FROM cur2 INTO @hh;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM #r;
        INSERT INTO #r EXEC dbo.usp_confirmar_verificacion_correo @tokenHash = @hh, @idCorrelacion = @corr;
        SET @malos += (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgInv);
        FETCH NEXT FROM cur2 INTO @hh;
    END
    CLOSE cur2; DEALLOCATE cur2;
    IF @malos <> 5
        THROW 55063, 'TEST FAILED DB-C02: los 5 tokens invalidos debian responder VCE_002 con estado 0.', 1;
    IF (SELECT correoConfirmado FROM dbo.Usuario WHERE id = @idUsuarioInactivo) <> 0
        THROW 55064, 'TEST FAILED DB-C02: un usuario inactivo no debe quedar verificado.', 1;
    PRINT 'TEST_PASS:DB-C02';

    -- =========================================================================
    -- DB-R01..R03: reenvio (ambito, ya verificado, espera minima)
    -- =========================================================================
    PRINT '-> DB-R01: ambito del reenvio';
    DECLARE @correoReenvio NVARCHAR(255) = CONCAT(N'ident001.reenvio.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @dominio);
    DELETE FROM #r;
    INSERT INTO #r
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @idGrupo = @grupo, @numeroIdentificacion = @n_30,
        @primerNombre = N'Ident', @segundoNombre = N'Cero', @primerApellido = N'Reenvio', @segundoApellido = N'Prueba',
        @correo = @correoReenvio, @password = N'HashBackend_Ident001_1234567890',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @userTitular, @idTipoIdIdentificacion = @tipoCC;
    DECLARE @usuarioReenvio UNIQUEIDENTIFIER = (SELECT id FROM dbo.Usuario WHERE correo = LOWER(@correoReenvio));
    DECLARE @estudianteReenvio UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estudiante WHERE usuario = @usuarioReenvio);
    IF @usuarioReenvio IS NULL OR @estudianteReenvio IS NULL
        THROW 55070, 'TEST FAILED DB-R01: fixture del reenvio no se creo.', 1;

    CREATE TABLE #reenvio (idUsuario UNIQUEIDENTIFIER NULL);
    INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_verificacion_correo
        @idGrupo = @grupo, @idEstudiante = @estudianteReenvio, @idUsuarioEjecutor = @userTitular, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #reenvio WHERE idUsuario = @usuarioReenvio) <> 1
        THROW 55071, 'TEST FAILED DB-R01: el docente titular debio obtener el usuario del estudiante.', 1;

    DELETE FROM #reenvio;
    INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_verificacion_correo
        @idGrupo = @grupo, @idEstudiante = @estudianteReenvio, @idUsuarioEjecutor = @userCoordPrograma, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #reenvio WHERE idUsuario = @usuarioReenvio) <> 1
        THROW 55072, 'TEST FAILED DB-R01: el coordinador del programa debio obtener el usuario del estudiante.', 1;

    DECLARE @capturado NVARCHAR(4000) = N'';
    BEGIN TRY
        DELETE FROM #reenvio;
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_verificacion_correo
            @idGrupo = @grupo, @idEstudiante = @estudianteReenvio, @idUsuarioEjecutor = @userOtroDocente, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=VCE_004%'
        THROW 55073, 'TEST FAILED DB-R01: un docente no titular debio recibir VCE_004.', 1;
    PRINT 'TEST_PASS:DB-R01';

    PRINT '-> DB-R03: espera minima entre reenvios (VCE_003)';
    DECLARE @h4 VARBINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ident001-token-4'));
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_emitir_token_verificacion_correo @idUsuario = @usuarioReenvio, @tokenHash = @h4, @idCorrelacion = @corr;
    SET @capturado = N'';
    BEGIN TRY
        DELETE FROM #reenvio;
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_verificacion_correo
            @idGrupo = @grupo, @idEstudiante = @estudianteReenvio, @idUsuarioEjecutor = @userTitular, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=VCE_003%'
        THROW 55074, 'TEST FAILED DB-R03: un reenvio inmediato debio recibir VCE_003.', 1;
    PRINT 'TEST_PASS:DB-R03';

    PRINT '-> DB-R02: reenvio a un correo ya verificado (VCE_005)';
    UPDATE dbo.Usuario SET correoConfirmado = 1 WHERE id = @usuarioReenvio;
    SET @capturado = N'';
    BEGIN TRY
        DELETE FROM #reenvio;
        INSERT INTO #reenvio EXEC dbo.usp_consultar_reenvio_verificacion_correo
            @idGrupo = @grupo, @idEstudiante = @estudianteReenvio, @idUsuarioEjecutor = @userTitular, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @capturado = ERROR_MESSAGE();
    END CATCH
    IF @capturado NOT LIKE N'%DBCODE=VCE_005%'
        THROW 55075, 'TEST FAILED DB-R02: un correo verificado debio recibir VCE_005.', 1;
    PRINT 'TEST_PASS:DB-R02';

    -- =========================================================================
    -- DB-P01: permisos del rol de runtime
    -- =========================================================================
    PRINT '-> DB-P01: permisos del rol de runtime';
    IF (SELECT COUNT(*) FROM sys.database_permissions p
        INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id AND r.name = N'rol_asistencias_runtime'
        WHERE p.permission_name = 'EXECUTE' AND p.state_desc = 'GRANT'
          AND p.major_id IN (OBJECT_ID(N'dbo.usp_emitir_token_verificacion_correo'), OBJECT_ID(N'dbo.usp_consultar_token_verificacion_correo'),
                             OBJECT_ID(N'dbo.usp_confirmar_verificacion_correo'), OBJECT_ID(N'dbo.usp_consultar_reenvio_verificacion_correo'))) <> 4
        THROW 55080, 'TEST FAILED DB-P01: el rol runtime debe tener EXECUTE sobre los 4 SP de IDENT-001.', 1;
    IF EXISTS (SELECT 1 FROM sys.database_permissions p
        INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id AND r.name = N'rol_asistencias_runtime'
        WHERE p.major_id = OBJECT_ID(N'dbo.TokenVerificacionCorreo') AND p.permission_name IN ('SELECT','INSERT','UPDATE','DELETE') AND p.state_desc = 'GRANT')
        THROW 55081, 'TEST FAILED DB-P01: el rol runtime no debe tener DML directo sobre dbo.TokenVerificacionCorreo.', 1;
    PRINT 'TEST_PASS:DB-P01';

    -- =========================================================================
    -- DB-M01: parametros y mensajes sembrados
    -- =========================================================================
    PRINT '-> DB-M01: parametros y mensajes sembrados';
    IF dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS') IS NULL
       OR dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS') <= 0
        THROW 55090, 'TEST FAILED DB-M01: parametro REENVIO_ESPERA_MINUTOS ausente.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('VCE_001','VCE_002','VCE_003','VCE_004','VCE_005','VCE_006') AND estaActivo = 1) <> 6
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('VCE_001','VCE_002','VCE_003','VCE_004','VCE_005','VCE_006') AND estaActivo = 1) <> 6
        THROW 55091, 'TEST FAILED DB-M01: faltan mensajes VCE_001..VCE_006 (usuario/tecnico).', 1;
    PRINT 'TEST_PASS:DB-M01';

    -- =========================================================================
    -- DB-L01: plantilla VERIFICACION_CORREO sembrada con marcadores obligatorios
    -- =========================================================================
    PRINT '-> DB-L01: plantilla VERIFICACION_CORREO v1';
    IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'VERIFICACION_CORREO' AND idioma = 'es' AND version = 1 AND activa = 1)
        THROW 55095, 'TEST FAILED DB-L01: falta la plantilla VERIFICACION_CORREO v1 activa.', 1;
    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador m
        WHERE m.tipo = 'VERIFICACION_CORREO' AND m.marcador IN ('nombre','enlace') AND m.obligatorio = 1) <> 2
        THROW 55096, 'TEST FAILED DB-L01: marcadores obligatorios nombre y enlace ausentes.', 1;
    PRINT 'TEST_PASS:DB-L01';

    DROP TABLE #reenvio;
    DROP TABLE #tok;
    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF USER_NAME() <> 'dbo' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

-- =========================================================================
-- DB-G01: @@TRANCOUNT = 0 al terminar
-- =========================================================================
IF @@TRANCOUNT <> 0
    THROW 55199, 'TEST FAILED DB-G01: test_ident001_correo_verificacion dejo transacciones abiertas.', 1;

PRINT 'TEST_PASS:DB-G01';
PRINT '==================================================';
PRINT 'TEST PASS: test_ident001_correo_verificacion (OK)';
PRINT '==================================================';
PRINT 'TEST_PASS:TEST_IDENT001_CORREO_VERIFICACION';
GO
