USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_crear_docente';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idProgramaValido UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa WHERE idCoordinador IS NOT NULL);
DECLARE @idCoordinadorTitular UNIQUEIDENTIFIER = (SELECT TOP 1 idCoordinador FROM dbo.uv_programa WHERE id = @idProgramaValido);
DECLARE @idUsuarioCoordinador UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE id = @idCoordinadorTitular);
DECLARE @idUsuarioEstudiante UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE estaActivoUsuario = 1);

IF @tipoId IS NULL THROW 51850, 'TEST FAILED: no existe fixture uv_tipo_identificacion CC.', 1;
IF @idProgramaValido IS NULL THROW 51851, 'TEST FAILED: no existe fixture uv_programa con coordinador.', 1;
IF @idCoordinadorTitular IS NULL THROW 51852, 'TEST FAILED: programa fixture no expone coordinador.', 1;
IF @idUsuarioCoordinador IS NULL THROW 51853, 'TEST FAILED: no existe fixture usuario coordinador.', 1;
IF @idUsuarioEstudiante IS NULL THROW 51854, 'TEST FAILED: no existe fixture usuario estudiante.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #docenteResultado (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );

    -- Caso 1: Sin @idUsuarioEjecutor (Fail-Closed -> GEN_002)
    DECLARE @corrNullExec UNIQUEIDENTIFIER = NEWID();
    DECLARE @correo1 NVARCHAR(100) = N'docente.nullexec.qa@test.local';
    INSERT INTO #docenteResultado
    EXEC dbo.usp_crear_docente
        @idDocente = NULL,
        @numeroIdentificacion = 918000001,
        @primerNombre = N'Docente',
        @segundoNombre = N'NullExec',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo1,
        @idPrograma = @idProgramaValido,
        @password = N'HashBackend_QaDocente1234567890',
        @idCorrelacion = @corrNullExec,
        @idUsuarioEjecutor = NULL;

    IF NOT EXISTS (SELECT 1 FROM #docenteResultado WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=GEN_002|%')
        THROW 51855, 'TEST FAILED: ejecutor NULL no retorno GEN_002.', 1;

    -- Caso 2: Ejecutor sin rol COORDINADOR (RBAC -> SEC_001)
    TRUNCATE TABLE #docenteResultado;
    DECLARE @corrRbacFail UNIQUEIDENTIFIER = NEWID();
    DECLARE @correo2 NVARCHAR(100) = N'docente.rbac.qa@test.local';
    INSERT INTO #docenteResultado
    EXEC dbo.usp_crear_docente
        @idDocente = NULL,
        @numeroIdentificacion = 918000002,
        @primerNombre = N'Docente',
        @segundoNombre = N'RbacFail',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo2,
        @idPrograma = @idProgramaValido,
        @password = N'HashBackend_QaDocente1234567890',
        @idCorrelacion = @corrRbacFail,
        @idUsuarioEjecutor = @idUsuarioEstudiante;

    IF NOT EXISTS (SELECT 1 FROM #docenteResultado WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=SEC_001|%')
        THROW 51856, 'TEST FAILED: ejecutor sin rol COORDINADOR no retorno SEC_001.', 1;

    -- Caso 3: Programa inexistente (-> PROG_001)
    TRUNCATE TABLE #docenteResultado;
    DECLARE @corrProgMissing UNIQUEIDENTIFIER = NEWID();
    DECLARE @correo3 NVARCHAR(100) = N'docente.noprog.qa@test.local';
    INSERT INTO #docenteResultado
    EXEC dbo.usp_crear_docente
        @idDocente = NULL,
        @numeroIdentificacion = 918000003,
        @primerNombre = N'Docente',
        @segundoNombre = N'NoProg',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo3,
        @idPrograma = '17171717-1717-1717-1717-171717171717',
        @password = N'HashBackend_QaDocente1234567890',
        @idCorrelacion = @corrProgMissing,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #docenteResultado WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=PROG_001|%')
        THROW 51857, 'TEST FAILED: programa inexistente no retorno PROG_001.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo3)
        THROW 51858, 'TEST FAILED: programa inexistente creo Usuario parcial.', 1;

    -- Caso 4: Alta exitosa de nuevo docente (Usuario + Docente)
    TRUNCATE TABLE #docenteResultado;
    DECLARE @corrSuccess UNIQUEIDENTIFIER = NEWID();
    DECLARE @idDocenteSuccess UNIQUEIDENTIFIER = NEWID();
    DECLARE @correo4 NVARCHAR(100) = N'docente.success.qa@test.local';
    INSERT INTO #docenteResultado
    EXEC dbo.usp_crear_docente
        @idDocente = @idDocenteSuccess,
        @numeroIdentificacion = 918000004,
        @primerNombre = N'Docente',
        @segundoNombre = N'Success',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo4,
        @idPrograma = @idProgramaValido,
        @password = N'HashBackend_QaDocente1234567890',
        @idCorrelacion = @corrSuccess,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #docenteResultado WHERE estadoResultado = 1)
        THROW 51859, 'TEST FAILED: creacion de docente valida no retorno SUCCESS.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuario u
        JOIN dbo.Docente d ON d.usuario = u.id
        WHERE u.correo = @correo4 AND d.id = @idDocenteSuccess
    )
        THROW 51860, 'TEST FAILED: creacion exitosa no inserto en Usuario y Docente.', 1;

    -- Caso 5: Idempotencia cuando el docente ya existe en dbo.Docente
    TRUNCATE TABLE #docenteResultado;
    DECLARE @corrIdemp UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #docenteResultado
    EXEC dbo.usp_crear_docente
        @idDocente = NULL,
        @numeroIdentificacion = 918000004,
        @primerNombre = N'Docente',
        @segundoNombre = N'Success',
        @primerApellido = N'QA',
        @segundoApellido = N'Test',
        @correo = @correo4,
        @idPrograma = @idProgramaValido,
        @password = NULL,
        @idCorrelacion = @corrIdemp,
        @idUsuarioEjecutor = @idUsuarioCoordinador;

    IF NOT EXISTS (SELECT 1 FROM #docenteResultado WHERE estadoResultado = 1)
        THROW 51861, 'TEST FAILED: revinculacion idempotente de docente existente no retorno SUCCESS.', 1;

    DROP TABLE #docenteResultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo IN (@correo1, @correo2, @correo3, @correo4))
    THROW 51862, 'TEST FAILED: test_usp_crear_docente dejo datos permanentes.', 1;

IF @@TRANCOUNT <> 0 THROW 51863, 'TEST FAILED: test_usp_crear_docente dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: docente SUCCESS/GEN_002/SEC_001/PROG_001/IDEMPOTENT.';
PRINT 'TEST_PASS:DOCENTE_CREATE_SUCCESS';
PRINT 'TEST END: test_usp_crear_docente';
GO
