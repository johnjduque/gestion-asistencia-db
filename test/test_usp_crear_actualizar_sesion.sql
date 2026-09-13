USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_crear_actualizar_sesion';

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
DECLARE @idDocenteTitular UNIQUEIDENTIFIER;

SELECT TOP 1
    @idGrupoValido = id,
    @idPeriodoValido = idPeriodoAcademico,
    @idDocenteTitular = idDocente
FROM dbo.uv_grupo
WHERE grupoEstaHablitado = 1
ORDER BY cuposDisponibles DESC;

IF @idGrupoValido IS NULL THROW 51300, 'TEST FAILED: no existe fixture uv_grupo habilitado.', 1;
IF @idDocenteTitular IS NULL THROW 51301, 'TEST FAILED: grupo fixture no expone docente titular.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #sesionResultado (
        idCorrelacion UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado BIT
    );
    DECLARE @corrCrear UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrIntrusa UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrActualizar UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrRenombrar UNIQUEIDENTIFIER = NEWID();

    UPDATE dbo.PeriodoAcademico
    SET fechaInicio = DATEADD(MONTH, -1, GETDATE()), fechaFin = DATEADD(MONTH, 3, GETDATE())
    WHERE id = @idPeriodoValido;

    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @idDocente = @idDocenteTitular,
        @nombre = N'Sesion Suite QA',
        @descripcion = N'Clase magistral de repaso',
        @fechaHoraInicio = NULL,
        @fechaHoraFin = NULL,
        @aula = N'Lab 301',
        @tipo = N'TEORICA',
        @idCorrelacion = @corrCrear;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 51302, 'TEST FAILED: usp_crear_sesion no retorno SUCCESS.', 1;

    DECLARE @idSesionCreada UNIQUEIDENTIFIER = (
        SELECT TOP 1 id FROM dbo.uv_sesion WHERE idGrupo = @idGrupoValido AND nombre = N'Sesion Suite QA' ORDER BY numero DESC
    );

    IF @idSesionCreada IS NULL THROW 51303, 'TEST FAILED: no se encontro sesion creada por uv_sesion.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesionCreada AND descripcion = N'Clase magistral de repaso' AND aula = N'Lab 301' AND tipo = N'TEORICA')
        THROW 51304, 'TEST FAILED: dbo.Sesion no persistio descripcion/aula/tipo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion WHERE id = @idSesionCreada AND descripcion = N'Clase magistral de repaso' AND aula = N'Lab 301' AND tipo = N'TEORICA')
        THROW 51305, 'TEST FAILED: uv_sesion no expone descripcion/aula/tipo.', 1;

    DECLARE @otroDocente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente WHERE id <> @idDocenteTitular);
    IF @otroDocente IS NULL
    BEGIN
        DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
        DECLARE @usuarioOtroDocente UNIQUEIDENTIFIER = '23232323-2323-2323-2323-232323232323';
        SET @otroDocente = '24242424-2424-2424-2424-242424242424';
        IF @tipoId IS NULL THROW 51306, 'TEST FAILED: no existe tipo identificacion CC para docente temporal.', 1;

        INSERT INTO dbo.Usuario (
            id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido,
            primerNombre, segundoNombre, correo, correoConfirmado, estado, password
        )
        VALUES (
            @usuarioOtroDocente, @tipoId, 913000001, N'Docente', N'Intruso',
            N'Sesion', N'QA', N'sesion.otrodocente.qa@test.local', 1, 1, N'HashBackend_QaSesion1234567890'
        );

        INSERT INTO dbo.Docente (id, usuario)
        VALUES (@otroDocente, @usuarioOtroDocente);
    END

    DECLARE @conteoAntes INT = (SELECT COUNT(1) FROM dbo.Sesion WHERE grupo = @idGrupoValido);
    TRUNCATE TABLE #sesionResultado;

    INSERT INTO #sesionResultado
    EXEC dbo.usp_crear_sesion
        @idGrupo = @idGrupoValido,
        @idDocente = @otroDocente,
        @nombre = N'Sesion Intrusa',
        @descripcion = NULL,
        @fechaHoraInicio = NULL,
        @fechaHoraFin = NULL,
        @aula = NULL,
        @tipo = NULL,
        @idCorrelacion = @corrIntrusa;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 0)
        THROW 51307, 'TEST FAILED: docente no titular no fue rechazado.', 1;

    IF @conteoAntes <> (SELECT COUNT(1) FROM dbo.Sesion WHERE grupo = @idGrupoValido)
        THROW 51308, 'TEST FAILED: docente no titular inserto una sesion.', 1;

    TRUNCATE TABLE #sesionResultado;
    INSERT INTO #sesionResultado
    EXEC dbo.usp_actualizar_sesion
        @idSesion = @idSesionCreada,
        @nombre = NULL,
        @fechaHoraInicio = NULL,
        @fechaHoraFin = NULL,
        @aula = N'Lab 405',
        @descripcion = N'Descripcion actualizada',
        @idDocente = NULL,
        @idCorrelacion = @corrActualizar;

    IF NOT EXISTS (SELECT 1 FROM #sesionResultado WHERE estadoResultado = 1)
        THROW 51309, 'TEST FAILED: usp_actualizar_sesion no retorno SUCCESS.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesionCreada AND aula = N'Lab 405' AND descripcion = N'Descripcion actualizada' AND tipo = N'TEORICA')
        THROW 51310, 'TEST FAILED: actualizar sesion no persistio aula/descripcion o perdio tipo.', 1;

    TRUNCATE TABLE #sesionResultado;
    INSERT INTO #sesionResultado
    EXEC dbo.usp_actualizar_sesion
        @idSesion = @idSesionCreada,
        @nombre = N'Sesion Renombrada',
        @fechaHoraInicio = NULL,
        @fechaHoraFin = NULL,
        @aula = NULL,
        @descripcion = NULL,
        @idDocente = NULL,
        @idCorrelacion = @corrRenombrar;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @idSesionCreada AND aula = N'Lab 405' AND descripcion = N'Descripcion actualizada' AND nombre = N'Sesion Renombrada')
        THROW 51311, 'TEST FAILED: actualizar sesion con NULL no conservo aula/descripcion.', 1;

    DROP TABLE #sesionResultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre IN (N'Sesion Suite QA', N'Sesion Intrusa', N'Sesion Renombrada'))
    THROW 51312, 'TEST FAILED: sesion dejo datos permanentes.', 1;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'sesion.otrodocente.qa@test.local')
    THROW 51313, 'TEST FAILED: sesion dejo docente temporal permanente.', 1;

IF @@TRANCOUNT <> 0 THROW 51314, 'TEST FAILED: sesion dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: sesion create/update/descripcion/aula/tipo/uv_sesion.';
PRINT 'TEST_PASS:SESSION_CREATE';
PRINT 'TEST_PASS:SESSION_UPDATE';
PRINT 'TEST_PASS:SESSION_NON_OWNER';
PRINT 'TEST END: test_usp_crear_actualizar_sesion';
GO
