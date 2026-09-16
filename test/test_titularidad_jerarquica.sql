USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_titularidad_jerarquica';

-- Fixtures reales de seed: Usuario.id (dominio Usuario) es explicitamente DISTINTO del id de la
-- entidad institucional (Docente.id / Coordinador.id / Decano.id) para evitar falsos positivos
-- por coincidencia accidental de UUID.
DECLARE @usuarioDocenteTitular     UNIQUEIDENTIFIER = 'E1F2A3B4-0000-0000-0000-000000000003';
DECLARE @docenteTitular            UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000003';
DECLARE @grupoTitular              UNIQUEIDENTIFIER = 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D';
DECLARE @sesionTitular             UNIQUEIDENTIFIER = 'B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E';

DECLARE @usuarioCoordinadorTitular UNIQUEIDENTIFIER = 'E1F2A3B4-0000-0000-0000-000000000002';
DECLARE @coordinadorTitular        UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000002';
DECLARE @programaTitular           UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';

DECLARE @usuarioDecanoTitular      UNIQUEIDENTIFIER = 'E1F2A3B4-0000-0000-0000-000000000001';
DECLARE @decanoTitular             UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000001';
DECLARE @facultadTitular           UNIQUEIDENTIFIER = 'A2B3C4D5-0000-0000-0000-000000000001';

IF NOT EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id = @grupoTitular AND idDocente = @docenteTitular)
    THROW 51700, 'TEST FAILED: fixture Grupo/Docente titular ausente.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @programaTitular AND idCoordinador = @coordinadorTitular)
    THROW 51701, 'TEST FAILED: fixture Programa/Coordinador titular ausente.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @facultadTitular AND idDecano = @decanoTitular)
    THROW 51702, 'TEST FAILED: fixture Facultad/Decano titular ausente.', 1;

-- CASO C: demostracion explicita de que Usuario.id != id de la entidad institucional
IF @usuarioDocenteTitular = @docenteTitular
    THROW 51703, 'TEST FAILED: fixture invalida, Usuario.id coincide con Docente.id (falso positivo posible).', 1;
IF @usuarioCoordinadorTitular = @coordinadorTitular
    THROW 51704, 'TEST FAILED: fixture invalida, Usuario.id coincide con Coordinador.id (falso positivo posible).', 1;
IF @usuarioDecanoTitular = @decanoTitular
    THROW 51705, 'TEST FAILED: fixture invalida, Usuario.id coincide con Decano.id (falso positivo posible).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_docente_identidad WHERE id = @docenteTitular AND idUsuario = @usuarioDocenteTitular)
    THROW 51706, 'TEST FAILED: relacion Usuario->Docente esperada no se cumple para el fixture.', 1;
PRINT 'TEST_PASS:TITULARIDAD_UUID_USUARIO_DISTINTO_DE_ROL';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000), @status BIT;

    -- CASO A (Docente propietario): GRUPO y SESION -> AUTORIZADO
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDocenteTitular, @idEntidadPadre = @grupoTitular, @tipoEntidadPadre = 'GRUPO',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 1 THROW 51707, 'TEST FAILED: docente titular rechazado sobre su propio Grupo.', 1;

    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDocenteTitular, @idEntidadPadre = @sesionTitular, @tipoEntidadPadre = 'SESION',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 1 THROW 51708, 'TEST FAILED: docente titular rechazado sobre su propia Sesion.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_DOCENTE_PROPIETARIO';

    -- CASO A (Coordinador propietario): PROGRAMA -> AUTORIZADO
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioCoordinadorTitular, @idEntidadPadre = @programaTitular, @tipoEntidadPadre = 'PROGRAMA',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 1 THROW 51709, 'TEST FAILED: coordinador titular rechazado sobre su propio Programa.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_COORDINADOR_PROPIETARIO';

    -- CASO A (Decano propietario): FACULTAD -> AUTORIZADO
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDecanoTitular, @idEntidadPadre = @facultadTitular, @tipoEntidadPadre = 'FACULTAD',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 1 THROW 51710, 'TEST FAILED: decano titular rechazado sobre su propia Facultad.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_DECANO_PROPIETARIO';

    -- Fixtures ajenas: Usuario+Docente, Usuario+Coordinador y Usuario+Decano reales que NO son titulares
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
    IF @tipoCC IS NULL THROW 51711, 'TEST FAILED: no existe fixture TipoIdentificacion CC.', 1;

    DECLARE @usuarioDocenteAjeno UNIQUEIDENTIFIER = NEWID(), @docenteAjeno UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioDocenteAjeno, @tipoCC, 940000001, N'Ajeno', N'Docente', N'QA', N'Titularidad', N'qa.docente.ajeno@test.local', 1, 1, N'HashBackend_QaAjeno1234567890');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@docenteAjeno, @usuarioDocenteAjeno);

    DECLARE @usuarioCoordinadorAjeno UNIQUEIDENTIFIER = NEWID(), @coordinadorAjeno UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioCoordinadorAjeno, @tipoCC, 940000002, N'Ajeno', N'Coordinador', N'QA', N'Titularidad', N'qa.coordinador.ajeno@test.local', 1, 1, N'HashBackend_QaAjeno1234567890');
    INSERT INTO dbo.Coordinador (id, usuario) VALUES (@coordinadorAjeno, @usuarioCoordinadorAjeno);

    DECLARE @usuarioDecanoAjeno UNIQUEIDENTIFIER = NEWID(), @decanoAjeno UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioDecanoAjeno, @tipoCC, 940000003, N'Ajeno', N'Decano', N'QA', N'Titularidad', N'qa.decano.ajeno@test.local', 1, 1, N'HashBackend_QaAjeno1234567890');
    INSERT INTO dbo.Decano (id, usuario) VALUES (@decanoAjeno, @usuarioDecanoAjeno);

    -- CASO B (Docente ajeno): rechazado sobre Grupo/Sesion de otro docente
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDocenteAjeno, @idEntidadPadre = @grupoTitular, @tipoEntidadPadre = 'GRUPO',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 0 THROW 51712, 'TEST FAILED: docente ajeno autorizado indebidamente sobre Grupo de otro docente.', 1;

    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDocenteAjeno, @idEntidadPadre = @sesionTitular, @tipoEntidadPadre = 'SESION',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 0 THROW 51713, 'TEST FAILED: docente ajeno autorizado indebidamente sobre Sesion de otro docente.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_DOCENTE_AJENO_RECHAZADO';

    -- CASO B (Coordinador ajeno): rechazado sobre Programa de otro coordinador
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioCoordinadorAjeno, @idEntidadPadre = @programaTitular, @tipoEntidadPadre = 'PROGRAMA',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 0 THROW 51714, 'TEST FAILED: coordinador ajeno autorizado indebidamente sobre Programa de otro coordinador.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_COORDINADOR_AJENO_RECHAZADO';

    -- CASO B (Decano ajeno): rechazado sobre Facultad de otro decano
    SET @corr = NEWID();
    EXEC dbo.usp_validar_titularidad_jerarquica_interno
        @idUsuario = @usuarioDecanoAjeno, @idEntidadPadre = @facultadTitular, @tipoEntidadPadre = 'FACULTAD',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT, @estadoResultado = @status OUTPUT;
    IF @status <> 0 THROW 51715, 'TEST FAILED: decano ajeno autorizado indebidamente sobre Facultad de otro decano.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_DECANO_AJENO_RECHAZADO';

    -- Extremo a extremo: usp_registrar_asistencias_sesion respeta la cadena Usuario->Docente->Grupo->Sesion
    DECLARE @estudianteSeed UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000004';
    DECLARE @jsonAsistencia NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @estudianteSeed), N'","estado":"AN"}]');
    CREATE TABLE #tituResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado INT NOT NULL);

    SET @corr = NEWID();
    INSERT INTO #tituResult
    EXEC dbo.usp_registrar_asistencias_sesion
        @idSesion = @sesionTitular, @asistenciaJSON = @jsonAsistencia, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @usuarioDocenteAjeno;
    IF (SELECT TOP 1 estadoResultado FROM #tituResult WHERE idCorrelacion = @corr) <> 0
        THROW 51716, 'TEST FAILED: usp_registrar_asistencias_sesion acepto a un docente ajeno como ejecutor.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sesionTitular)
        THROW 51717, 'TEST FAILED: se persistio asistencia pese a titularidad rechazada.', 1;

    TRUNCATE TABLE #tituResult;
    SET @corr = NEWID();
    INSERT INTO #tituResult
    EXEC dbo.usp_registrar_asistencias_sesion
        @idSesion = @sesionTitular, @asistenciaJSON = @jsonAsistencia, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @usuarioDocenteTitular;
    IF (SELECT TOP 1 estadoResultado FROM #tituResult WHERE idCorrelacion = @corr) <> 1
        THROW 51718, 'TEST FAILED: usp_registrar_asistencias_sesion rechazo al docente titular real.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.uv_asistencia a
        INNER JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sesionTitular AND d.codigoRazonCausa = 'AN'
    )
        THROW 51719, 'TEST FAILED: asistencia del docente titular no quedo visible via uv_detalle_asistencia.', 1;
    PRINT 'TEST_PASS:TITULARIDAD_E2E_REGISTRO_ASISTENCIA';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo IN (N'qa.docente.ajeno@test.local', N'qa.coordinador.ajeno@test.local', N'qa.decano.ajeno@test.local'))
    THROW 51720, 'TEST FAILED: fixtures ajenas de titularidad quedaron persistidas.', 1;
IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = 'B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E')
    THROW 51721, 'TEST FAILED: test_titularidad_jerarquica dejo asistencia persistida en sesion seed.', 1;
IF @@TRANCOUNT <> 0 THROW 51722, 'TEST FAILED: test_titularidad_jerarquica dejo transaccion abierta.', 1;
PRINT 'TEST END: test_titularidad_jerarquica';
GO
