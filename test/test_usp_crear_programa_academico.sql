USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_programa_academico (HU076)';
PRINT '==================================================';

DECLARE @idFacultad UNIQUEIDENTIFIER = (
    SELECT TOP 1 f.id
    FROM dbo.uv_facultad f
    INNER JOIN dbo.uv_decano_identidad d ON f.idDecano = d.id
    WHERE f.estaActivaFacultad = 1 AND d.estaActivoUsuario = 1
    ORDER BY f.id
);

DECLARE @idUsuarioDecano UNIQUEIDENTIFIER = (
    SELECT TOP 1 d.idUsuario
    FROM dbo.uv_facultad f
    INNER JOIN dbo.uv_decano_identidad d ON f.idDecano = d.id
    WHERE f.id = @idFacultad
);

DECLARE @idCoordinador UNIQUEIDENTIFIER = (
    SELECT TOP 1 id
    FROM dbo.uv_coordinador_identidad
    WHERE estaActivoUsuario = 1
    ORDER BY id
);

DECLARE @idTipoPrograma UNIQUEIDENTIFIER = (
    SELECT TOP 1 id
    FROM dbo.uv_tipo_programa
    WHERE estaActivoTipoPrograma = 1
    ORDER BY id
);

DECLARE @idUsuarioNoDecano UNIQUEIDENTIFIER = (
    SELECT TOP 1 up.idUsuario
    FROM dbo.uv_usuario_perfil up
    WHERE up.estado = 1
      AND up.codigoPerfil <> 'DECANO'
      AND up.codigoPerfil <> 'DE'
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.uv_usuario_perfil decProfile
          WHERE decProfile.idUsuario = up.idUsuario
            AND decProfile.codigoPerfil IN ('DECANO', 'DE')
            AND decProfile.estado = 1
      )
    ORDER BY up.idUsuario
);

IF @idFacultad IS NULL THROW 51600, 'TEST FAILED: Fixture uv_facultad no disponible.', 1;
IF @idUsuarioDecano IS NULL THROW 51601, 'TEST FAILED: Fixture decano titular activo no disponible.', 1;
IF @idCoordinador IS NULL THROW 51602, 'TEST FAILED: Fixture uv_coordinador_identidad no disponible.', 1;
IF @idTipoPrograma IS NULL THROW 51603, 'TEST FAILED: Fixture uv_tipo_programa no disponible.', 1;
IF @idUsuarioNoDecano IS NULL THROW 51604, 'TEST FAILED: Fixture usuario no decano no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #programaResultado (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- =========================================================================
    -- CASO 1: El ejecutor es obligatorio y la ausencia falla cerrada (GEN_002)
    -- =========================================================================
    PRINT '-> Caso 1: Validando rechazo ante ejecutor nulo...';
    DECLARE @corr1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 101,
        @nombre = N'Programa Sin Ejecutor',
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr1,
        @idUsuarioEjecutor = NULL;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr1
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%'
    )
        THROW 51605, 'TEST FAILED: usp_crear_programa_academico no rechazo ejecutor nulo con GEN_002.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_EXECUTOR_REQUIRED';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 2: Un ejecutor sin perfil DECANO debe fallar cerrado (SEC_001)
    -- =========================================================================
    PRINT '-> Caso 2: Validando rechazo ante ejecutor sin perfil DECANO...';
    DECLARE @corr2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 102,
        @nombre = N'Programa Sin Rol Decano',
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr2,
        @idUsuarioEjecutor = @idUsuarioNoDecano;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr2
          AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%'
    )
        THROW 51606, 'TEST FAILED: usp_crear_programa_academico permitio ejecutor sin perfil DECANO.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_EXECUTOR_RBAC';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 3: Validación de nombre obligatorio y longitud mínima (3..50)
    -- =========================================================================
    PRINT '-> Caso 3: Validando rechazo ante nombre demasiado corto...';
    DECLARE @corr3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 103,
        @nombre = N'AB',
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr3,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr3
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%'
    )
        THROW 51607, 'TEST FAILED: usp_crear_programa_academico no rechazo nombre menor a 3 caracteres.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_NAME_VALIDATION';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 3.5: Validación de rechazo ante nombre con dígitos numéricos
    -- =========================================================================
    PRINT '-> Caso 3.5: Validando rechazo ante nombre con digitos numericos...';
    DECLARE @corr35 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 103,
        @nombre = N'Ingenieria 2',
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr35,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr35
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%'
    )
        THROW 51612, 'TEST FAILED: usp_crear_programa_academico permitio nombre con numeros.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_NO_NUMBERS_VALIDATION';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 4: Validación de integridad referencial de Tipo de Programa y Coordinador
    -- =========================================================================
    PRINT '-> Caso 4: Validando rechazo ante tipo de programa o coordinador inexistente...';
    DECLARE @corr4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 104,
        @nombre = N'Programa Tipo Invalido',
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = '99999999-9999-9999-9999-999999999999',
        @idCorrelacion = @corr4,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr4
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_001|%'
    )
        THROW 51608, 'TEST FAILED: usp_crear_programa_academico no rechazo tipo de programa inexistente.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_TYPE_FK_VALIDATION';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 5: Happy Path - Inserción exitosa de nuevo programa académico
    -- =========================================================================
    PRINT '-> Caso 5: Validando insercion exitosa de nuevo programa academico...';
    DECLARE @nombreValido NVARCHAR(50) = CONCAT(N'Programa QA ', CHAR(65 + ABS(CHECKSUM(NEWID())) % 26), CHAR(65 + ABS(CHECKSUM(NEWID())) % 26), CHAR(65 + ABS(CHECKSUM(NEWID())) % 26), CHAR(65 + ABS(CHECKSUM(NEWID())) % 26));
    DECLARE @idGenerado UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr5 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = @idGenerado,
        @codigo = 205,
        @nombre = @nombreValido,
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr5,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (SELECT 1 FROM #programaResultado WHERE estadoResultado = 1 AND idCorrelacion = @corr5)
        THROW 51609, 'TEST FAILED: usp_crear_programa_academico no retorno estadoResultado = 1 para programa valido.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.uv_programa
        WHERE id = @idGenerado
          AND nombrePrograma = @nombreValido
          AND idFacultad = @idFacultad
          AND idCoordinador = @idCoordinador
          AND idTipoPrograma = @idTipoPrograma
          AND estaActivoPrograma = 1
    )
        THROW 51610, 'TEST FAILED: No se encontro el programa persistido con tipo de programa en dbo.uv_programa.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_SUCCESS';
    TRUNCATE TABLE #programaResultado;

    -- =========================================================================
    -- CASO 6: Validación de Unicidad de Nombre (GEN_003) para nuevo programa
    -- =========================================================================
    PRINT '-> Caso 6: Validando rechazo ante nombre duplicado (GEN_003)...';
    DECLARE @corr6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #programaResultado
    EXEC dbo.usp_crear_programa_academico
        @idPrograma = NULL,
        @codigo = 206,
        @nombre = @nombreValido,
        @idCoordinador = @idCoordinador,
        @idFacultad = @idFacultad,
        @idTipoPrograma = @idTipoPrograma,
        @idCorrelacion = @corr6,
        @idUsuarioEjecutor = @idUsuarioDecano;

    IF NOT EXISTS (
        SELECT 1
        FROM #programaResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr6
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_003|%'
    )
        THROW 51611, 'TEST FAILED: usp_crear_programa_academico permitio duplicar nombre de programa.', 1;

    PRINT 'TEST_PASS:HU076_PROGRAM_CREATE_DUPLICATE_REJECTED';

    DROP TABLE #programaResultado;

    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado exitosamente. Cero residuos en la BD.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 51699, 'TEST FAILED: test_usp_crear_programa_academico dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_crear_programa_academico (HU076 OK)';
PRINT '==================================================';
GO
