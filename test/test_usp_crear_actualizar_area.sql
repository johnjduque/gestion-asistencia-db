USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_y_actualizar_area (HU151 / HU152)';
PRINT '==================================================';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER = (
    SELECT TOP 1 idUsuario
    FROM dbo.uv_administrador
    WHERE estaActivoAdministrador = 1
    ORDER BY idUsuario
);
DECLARE @idUsuarioNoAdministrador UNIQUEIDENTIFIER = (
    SELECT TOP 1 up.idUsuario
    FROM dbo.uv_usuario_perfil up
    WHERE up.estado = 1
      AND up.codigoPerfil <> 'AD'
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.uv_usuario_perfil adminProfile
          WHERE adminProfile.idUsuario = up.idUsuario
            AND adminProfile.codigoPerfil = 'AD'
            AND adminProfile.estado = 1
      )
    ORDER BY up.idUsuario
);

IF @idUsuarioEjecutor IS NULL THROW 51600, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idUsuarioNoAdministrador IS NULL THROW 51601, 'TEST FAILED: Fixture usuario no administrador no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #areaResultado (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- 1. Rechazo ante ejecutor nulo
    DECLARE @corr1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #areaResultado
    EXEC dbo.usp_crear_area
        @id = NULL,
        @codigo = N'TST',
        @nombre = N'Area Test Ejecutor Nulo',
        @idCorrelacion = @corr1,
        @idUsuarioEjecutor = NULL;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 0 AND idCorrelacion = @corr1)
        THROW 51602, 'TEST FAILED: usp_crear_area no rechazo ejecutor nulo.', 1;

    TRUNCATE TABLE #areaResultado;

    -- 2. Rechazo ante usuario sin rol administrador
    DECLARE @corrRbac UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #areaResultado
    EXEC dbo.usp_crear_area
        @id = NULL,
        @codigo = N'TST',
        @nombre = N'Area Test Sin RBAC',
        @idCorrelacion = @corrRbac,
        @idUsuarioEjecutor = @idUsuarioNoAdministrador;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 0 AND idCorrelacion = @corrRbac)
        THROW 51603, 'TEST FAILED: usp_crear_area permitio ejecutor sin perfil ADMINISTRADOR.', 1;

    TRUNCATE TABLE #areaResultado;

    -- 3. Rechazo ante código inválido (> 3 caracteres)
    DECLARE @corrCodigo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #areaResultado
    EXEC dbo.usp_crear_area
        @id = NULL,
        @codigo = N'TOOLONG',
        @nombre = N'Area Codigo Largo',
        @idCorrelacion = @corrCodigo,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 0 AND idCorrelacion = @corrCodigo)
        THROW 51604, 'TEST FAILED: usp_crear_area permitio codigo mayor a 3 caracteres.', 1;

    TRUNCATE TABLE #areaResultado;

    -- 4. Creación Exitosa (Happy Path)
    DECLARE @idAreaValida UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrSuccess UNIQUEIDENTIFIER = NEWID();
    DECLARE @codigoValido NVARCHAR(3) = N'QA1';
    DECLARE @nombreValido NVARCHAR(50) = N'Area QA Pruebas Unitarias';

    INSERT INTO #areaResultado
    EXEC dbo.usp_crear_area
        @id = @idAreaValida,
        @codigo = @codigoValido,
        @nombre = @nombreValido,
        @idCorrelacion = @corrSuccess,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 1 AND idCorrelacion = @corrSuccess)
        THROW 51605, 'TEST FAILED: usp_crear_area fallo al crear area valida.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @idAreaValida AND codigo = @codigoValido AND nombre = @nombreValido)
        THROW 51606, 'TEST FAILED: El area creada no se visualiza en dbo.uv_area.', 1;

    TRUNCATE TABLE #areaResultado;

    -- 5. Rechazo ante duplicidad de Código
    DECLARE @corrDupCod UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #areaResultado
    EXEC dbo.usp_crear_area
        @id = NULL,
        @codigo = @codigoValido,
        @nombre = N'Otra Area Con Mismo Codigo',
        @idCorrelacion = @corrDupCod,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 0 AND idCorrelacion = @corrDupCod)
        THROW 51607, 'TEST FAILED: usp_crear_area permitio duplicar codigo.', 1;

    TRUNCATE TABLE #areaResultado;

    -- 6. Actualización Exitosa (Happy Path de HU152)
    DECLARE @corrUpdate UNIQUEIDENTIFIER = NEWID();
    DECLARE @nuevoCodigo NVARCHAR(3) = N'QA2';
    DECLARE @nuevoNombre NVARCHAR(50) = N'Area QA Pruebas Modificada';

    INSERT INTO #areaResultado
    EXEC dbo.usp_actualizar_area
        @id = @idAreaValida,
        @codigo = @nuevoCodigo,
        @nombre = @nuevoNombre,
        @idCorrelacion = @corrUpdate,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #areaResultado WHERE estadoResultado = 1 AND idCorrelacion = @corrUpdate)
        THROW 51608, 'TEST FAILED: usp_actualizar_area fallo al actualizar.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @idAreaValida AND codigo = @nuevoCodigo AND nombre = @nuevoNombre)
        THROW 51609, 'TEST FAILED: uv_area no refleja los cambios tras usp_actualizar_area.', 1;

    TRUNCATE TABLE #areaResultado;

    DROP TABLE #areaResultado;

    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado exitosamente. Cero residuos.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_crear_y_actualizar_area (HU151/HU152 OK)';
PRINT '==================================================';
GO
