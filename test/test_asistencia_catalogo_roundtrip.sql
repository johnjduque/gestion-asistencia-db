USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_asistencia_catalogo_roundtrip';

DECLARE @grupo UNIQUEIDENTIFIER = 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D';
DECLARE @estudianteA UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000004';
DECLARE @estudianteB UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000005';
DECLARE @enrollmentA UNIQUEIDENTIFIER, @enrollmentB UNIQUEIDENTIFIER;
SELECT @enrollmentA = id FROM dbo.uv_estudiante_grupo WHERE idEstudiante = @estudianteA AND idGrupo = @grupo;
SELECT @enrollmentB = id FROM dbo.uv_estudiante_grupo WHERE idEstudiante = @estudianteB AND idGrupo = @grupo;
IF @enrollmentA IS NULL OR @enrollmentB IS NULL
    THROW 51600, 'TEST FAILED: fixtures de matricula del Grupo seed ausentes.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.uv_razon_causa WHERE codigo = 'AN')
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_razon_causa WHERE codigo = 'SJC')
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_razon_causa WHERE codigo = 'EX')
    THROW 51601, 'TEST FAILED: catalogo RazonCausa no expone AN/SJC/EX.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @estadoActivo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
    IF @tipoCC IS NULL OR @estadoActivo IS NULL THROW 51602, 'TEST FAILED: fixtures de catalogo ausentes.', 1;

    -- Tercer estudiante ad-hoc matriculado en el mismo Grupo, exclusivo de esta prueba
    DECLARE @usuarioC UNIQUEIDENTIFIER = NEWID(), @estudianteC UNIQUEIDENTIFIER = NEWID(), @enrollmentC UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@usuarioC, @tipoCC, 941000001, N'RoundTrip', N'QA', N'Estudiante', N'Tercero', N'qa.estudiante.roundtrip@test.local', 1, 1, N'HashBackend_QaRoundTrip1234567890');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@estudianteC, @usuarioC);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@enrollmentC, @estadoActivo, @estudianteC, @grupo);

    DECLARE @sesionRoundtrip UNIQUEIDENTIFIER = NEWID();
    DECLARE @firstNumber INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @grupo);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesionRoundtrip, N'QA Roundtrip AN-SJC-EX', @firstNumber, CONCAT(N'QA-RT-', @firstNumber), 1, @grupo, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    DECLARE @jsonRoundtrip NVARCHAR(MAX) = (
        SELECT idEstudiante, estado FROM (VALUES
            (@estudianteA, N'AN'),
            (@estudianteB, N'SJC'),
            (@estudianteC, N'EX')
        ) AS T(idEstudiante, estado)
        FOR JSON PATH
    );
    DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
    CREATE TABLE #rtResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado INT NOT NULL);

    SET @corr = NEWID();
    INSERT INTO #rtResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sesionRoundtrip, @asistenciaJSON = @jsonRoundtrip, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #rtResult WHERE idCorrelacion = @corr) <> 1
        THROW 51603, 'TEST FAILED: ROUNDTRIP_AN_SJC_EX lote valido fue rechazado.', 1;
    PRINT 'TEST_PASS:ROUNDTRIP_BATCH_AN_SJC_EX_SUCCESS';

    -- Round-trip EXACTO via vistas publicas: AN debe seguir siendo AN, no solo asistio=1;
    -- SJC y EX deben distinguirse entre si y no colapsar al mismo booleano.
    IF NOT EXISTS (
        SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sesionRoundtrip AND a.idEstudianteGrupo = @enrollmentA AND d.codigoRazonCausa = 'AN' AND d.asistio = 1
    ) THROW 51604, 'TEST FAILED: ROUNDTRIP estudiante A no quedo como AN exacto.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sesionRoundtrip AND a.idEstudianteGrupo = @enrollmentB AND d.codigoRazonCausa = 'SJC' AND d.asistio = 0
    ) THROW 51605, 'TEST FAILED: ROUNDTRIP estudiante B no quedo como SJC exacto.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sesionRoundtrip AND a.idEstudianteGrupo = @enrollmentC AND d.codigoRazonCausa = 'EX' AND d.asistio = 0
    ) THROW 51606, 'TEST FAILED: ROUNDTRIP estudiante C no quedo como EX exacto.', 1;
    IF EXISTS (
        SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sesionRoundtrip AND a.idEstudianteGrupo = @enrollmentB AND d.codigoRazonCausa = 'EX'
    ) THROW 51607, 'TEST FAILED: ROUNDTRIP SJC y EX colapsaron al mismo codigo.', 1;
    PRINT 'TEST_PASS:ROUNDTRIP_AN_SJC_EX_EXACT_MATCH';

    -- Codigo invalido: no debe crear una nueva RazonCausa dinamica
    DECLARE @conteoRazonCausaAntes INT = (SELECT COUNT(1) FROM dbo.RazonCausa);
    DECLARE @sesionInvalida UNIQUEIDENTIFIER = NEWID();
    SET @firstNumber = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @grupo);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesionInvalida, N'QA Codigo Invalido', @firstNumber, CONCAT(N'QA-RT-', @firstNumber), 1, @grupo, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    DECLARE @jsonInvalido NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @estudianteA), N'","estado":"ABC"}]');
    TRUNCATE TABLE #rtResult;
    SET @corr = NEWID();
    INSERT INTO #rtResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sesionInvalida, @asistenciaJSON = @jsonInvalido, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #rtResult WHERE idCorrelacion = @corr) <> 0
        THROW 51608, 'TEST FAILED: CODIGO_INVALIDO_ABC fue aceptado indebidamente.', 1;
    IF EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'ABC')
        THROW 51609, 'TEST FAILED: se creo dinamicamente una RazonCausa con codigo ABC.', 1;
    IF (SELECT COUNT(1) FROM dbo.RazonCausa) <> @conteoRazonCausaAntes
        THROW 51610, 'TEST FAILED: el catalogo RazonCausa crecio tras un codigo invalido.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sesionInvalida)
        THROW 51611, 'TEST FAILED: CODIGO_INVALIDO_ABC persistio asistencia pese al rechazo.', 1;
    PRINT 'TEST_PASS:RAZON_CAUSA_CODIGO_INVALIDO_RECHAZADO';
    PRINT 'TEST_PASS:RAZON_CAUSA_SIN_CREACION_DINAMICA';

    -- Atomicidad: lote mixto (AN valido + ABC invalido) debe fallar completo, 0 cambios parciales
    DECLARE @sesionMixta UNIQUEIDENTIFIER = NEWID();
    SET @firstNumber = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @grupo);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesionMixta, N'QA Lote Mixto', @firstNumber, CONCAT(N'QA-RT-', @firstNumber), 1, @grupo, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    DECLARE @jsonMixto NVARCHAR(MAX) = (
        SELECT idEstudiante, estado FROM (VALUES
            (@estudianteA, N'AN'),
            (@estudianteB, N'ABC'),
            (@estudianteC, N'EX')
        ) AS T(idEstudiante, estado)
        FOR JSON PATH
    );
    TRUNCATE TABLE #rtResult;
    SET @corr = NEWID();
    INSERT INTO #rtResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sesionMixta, @asistenciaJSON = @jsonMixto, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #rtResult WHERE idCorrelacion = @corr) <> 0
        THROW 51612, 'TEST FAILED: LOTE_MIXTO fue aceptado pese a contener un codigo invalido.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sesionMixta)
        THROW 51613, 'TEST FAILED: LOTE_MIXTO dejo cambios parciales persistidos (rollback incompleto).', 1;
    PRINT 'TEST_PASS:ATOMICIDAD_LOTE_MIXTO_ROLLBACK_TOTAL';

    -- Integridad: estudiante que NO pertenece al Grupo de la Sesion -> rechazado, sin persistencia
    DECLARE @asignatura UNIQUEIDENTIFIER = (SELECT TOP 1 idAsignatura FROM dbo.uv_grupo WHERE id = @grupo);
    DECLARE @periodo UNIQUEIDENTIFIER = (SELECT TOP 1 idPeriodoAcademico FROM dbo.uv_grupo WHERE id = @grupo);
    DECLARE @docenteTitular UNIQUEIDENTIFIER = (SELECT TOP 1 docente FROM dbo.Grupo WHERE id = @grupo);
    DECLARE @grupoAjeno UNIQUEIDENTIFIER = NEWID();
    DECLARE @codigoGrupoAjeno INT = 90000 + ABS(CHECKSUM(NEWID()) % 9000);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grupoAjeno, @asignatura, @periodo, @codigoGrupoAjeno, N'QA Grupo Ajeno Integridad', 30, 0, 0, 0, @docenteTitular);

    DECLARE @sesionGrupoAjeno UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesionGrupoAjeno, N'QA Sesion Grupo Ajeno', 1, N'QA-GA-01', 1, @grupoAjeno, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    DECLARE @jsonEstudianteFueraDeGrupo NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @estudianteA), N'","estado":"AN"}]');
    TRUNCATE TABLE #rtResult;
    SET @corr = NEWID();
    INSERT INTO #rtResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sesionGrupoAjeno, @asistenciaJSON = @jsonEstudianteFueraDeGrupo, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #rtResult WHERE idCorrelacion = @corr) <> 0
        THROW 51614, 'TEST FAILED: se acepto asistencia de un estudiante que no pertenece al Grupo de la Sesion.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sesionGrupoAjeno)
        THROW 51615, 'TEST FAILED: se persistio asistencia de un estudiante ajeno al Grupo de la Sesion.', 1;
    PRINT 'TEST_PASS:INTEGRIDAD_ESTUDIANTE_FUERA_DE_GRUPO_RECHAZADO';

    -- Integridad: sesion inexistente -> rechazada, sin persistencia
    DECLARE @sesionInexistente UNIQUEIDENTIFIER = NEWID();
    TRUNCATE TABLE #rtResult;
    SET @corr = NEWID();
    INSERT INTO #rtResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sesionInexistente, @asistenciaJSON = @jsonEstudianteFueraDeGrupo, @idCorrelacion = @corr;
    IF (SELECT TOP 1 estadoResultado FROM #rtResult WHERE idCorrelacion = @corr) <> 0
        THROW 51616, 'TEST FAILED: se acepto una Sesion inexistente.', 1;
    PRINT 'TEST_PASS:INTEGRIDAD_SESION_INEXISTENTE_RECHAZADA';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'ABC')
    THROW 51617, 'TEST FAILED: fixture RazonCausa ABC quedo persistida tras rollback.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'qa.estudiante.roundtrip@test.local')
    THROW 51618, 'TEST FAILED: fixture de estudiante roundtrip quedo persistida tras rollback.', 1;
IF @@TRANCOUNT <> 0 THROW 51619, 'TEST FAILED: test_asistencia_catalogo_roundtrip dejo transaccion abierta.', 1;
PRINT 'TEST END: test_asistencia_catalogo_roundtrip';
GO
