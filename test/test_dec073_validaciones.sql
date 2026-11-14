USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- DEC-073 (revision exhaustiva de formularios, 2026-11-13) y DEC-072 en la base de datos (migracion 43):
--   * usp_validar_sesion_mismo_dia_interno: la sesion no cruza la medianoche en TIEMPO/ZONA_HORARIA_SQLSERVER (SES_028).
--   * usp_validar_correo_institucional_personal_interno: correo institucional del personal nuevo (VCE_008).
--   * usp_resolver_solicitud_revision_asistencia: respuesta obligatoria al rechazar (10..500), maximo al aprobar.
--   * usp_actualizar_asignatura: creditos hasta ASIGNATURA/CREDITOS_MAXIMO (ASI_008).
--   * usp_crear_grupo: codigo del grupo mayor que cero (ERR_CODIGO_GRUPO_INVALIDO).
PRINT 'TEST START: test_dec073_validaciones';

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @idPlan UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idProg = pe.idPrograma, @idPlan = pe.id
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_asignatura_plan_estudio apx ON apx.idAsignatura = a.id
INNER JOIN dbo.uv_semestre_plan_estudio spe ON apx.idSemestrePlanEstudio = spe.id
INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
INNER JOIN dbo.uv_programa pr ON pe.idPrograma = pr.id AND pr.idCoordinador IS NOT NULL;
SELECT @uCoord = ci.idUsuario FROM dbo.uv_programa pr INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador WHERE pr.id = @idProg;
DECLARE @idPeriodo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_periodo_academico ORDER BY anio DESC);
DECLARE @tvCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = 'CAT');
DECLARE @uDocente UNIQUEIDENTIFIER = (SELECT TOP 1 u.id FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.estado = 1 ORDER BY u.correo);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idPlan IS NULL OR @uCoord IS NULL OR @idPeriodo IS NULL OR @tvCat IS NULL OR @uDocente IS NULL
    THROW 53730, 'TEST FAILED: faltan fixtures del seed (asignatura con plan y coordinador, periodo, vinculacion o docente).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

    -- 1. Mismo dia en la zona institucional (Bogota, UTC-5): 08:00-10:00 local pasa
    EXEC dbo.usp_validar_sesion_mismo_dia_interno @fechaHoraInicio = '2026-11-20T13:00:00', @fechaHoraFin = '2026-11-20T15:00:00',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 53731, 'DEC073_SESSION_SAME_DAY_OK FAILED: 08:00-10:00 local debio pasar.', 1;
    -- 18:00-20:00 local cambia de dia en UTC pero no en la zona institucional: pasa
    EXEC dbo.usp_validar_sesion_mismo_dia_interno @fechaHoraInicio = '2026-11-20T23:00:00', @fechaHoraFin = '2026-11-21T01:00:00',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 53732, 'DEC073_SESSION_SAME_DAY_OK FAILED: 18:00-20:00 local cruza el dia UTC pero no el local.', 1;
    PRINT 'TEST_PASS:DEC073_SESSION_SAME_DAY_OK';

    -- 22:00-01:00 local cruza la medianoche: SES_028
    EXEC dbo.usp_validar_sesion_mismo_dia_interno @fechaHoraInicio = '2026-11-21T03:00:00', @fechaHoraFin = '2026-11-21T06:00:00',
        @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE 'DBCODE=SES[_]028|%' OR NULLIF(@mu, N'') IS NULL
        THROW 53733, 'DEC073_SESSION_CROSSES_MIDNIGHT FAILED: 22:00-01:00 local debio ser SES_028.', 1;
    PRINT 'TEST_PASS:DEC073_SESSION_CROSSES_MIDNIGHT';

    -- 2. Correo institucional del personal nuevo
    DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = N'decano.qa@gmail.com', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE 'DBCODE=VCE[_]008|%' OR CHARINDEX(@dominio, @mu) = 0
        THROW 53734, 'DEC073_STAFF_EMAIL_REJECTED FAILED: gmail debio ser VCE_008 con el dominio en el mensaje.', 1;
    PRINT 'TEST_PASS:DEC073_STAFF_EMAIL_REJECTED';

    DECLARE @correoUco NVARCHAR(255) = CONCAT(N'  Decano.QA', UPPER(@dominio), N' ');
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = @correoUco, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 53735, 'DEC073_STAFF_EMAIL_ACCEPTED FAILED: el dominio institucional (mayusculas y espacios) debio pasar.', 1;
    EXEC dbo.usp_validar_correo_institucional_personal_interno @correo = NULL, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 53736, 'DEC073_STAFF_EMAIL_ACCEPTED FAILED: sin correo no hay nada que validar.', 1;
    PRINT 'TEST_PASS:DEC073_STAFF_EMAIL_ACCEPTED';

    -- 3. Respuesta del reclamo (se valida antes de leer la solicitud: un id inexistente basta)
    DECLARE @sol UNIQUEIDENTIFIER = NEWID();
    DECLARE @idDoc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Docente WHERE usuario = @uDocente);
    INSERT INTO #r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @idDoc, @accion = N'RECHAZADA',
        @respuestaDocente = N'  corta  ', @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    INSERT INTO #r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @idDoc, @accion = N'RECHAZADA',
        @respuestaDocente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    DECLARE @larga NVARCHAR(MAX) = REPLICATE(CAST(N'x' AS NVARCHAR(MAX)), 501);
    INSERT INTO #r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @idDoc, @accion = N'APROBADA',
        @respuestaDocente = @larga, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ERR[_]RESPUESTA[_]RECLAMO[_]LONGITUD[_]INVALIDA|%') <> 3
        THROW 53737, 'DEC073_CLAIM_RESPONSE_LENGTH FAILED: rechazo corto o vacio y aprobacion de 501 debieron ser ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA.', 1;
    PRINT 'TEST_PASS:DEC073_CLAIM_RESPONSE_LENGTH';

    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @idDoc, @accion = N'APROBADA',
        @respuestaDocente = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    INSERT INTO #r EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = @idDoc, @accion = N'RECHAZADA',
        @respuestaDocente = N'No presentó soporte.', @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    IF EXISTS (SELECT 1 FROM #r WHERE mensajeTecnicoResultado LIKE 'DBCODE=ERR[_]RESPUESTA[_]RECLAMO[_]LONGITUD[_]INVALIDA|%')
       OR (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0) <> 2
        THROW 53738, 'DEC073_CLAIM_RESPONSE_VALID FAILED: aprobar sin respuesta y rechazar con 20 caracteres pasan la regla (y fallan despues por la solicitud inexistente).', 1;
    PRINT 'TEST_PASS:DEC073_CLAIM_RESPONSE_VALID';

    -- 4. Creditos de la asignatura: 11 supera ASIGNATURA/CREDITOS_MAXIMO (10)
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @idAsig, @codigo = NULL, @nombre = NULL, @creditos = 11,
        @idPlanEstudio = @idPlan, @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ASI[_]008|%')
        THROW 53739, 'DEC073_SUBJECT_CREDITS_MAX FAILED: 11 creditos debio ser ASI_008.', 1;
    PRINT 'TEST_PASS:DEC073_SUBJECT_CREDITS_MAX';

    -- 5. Codigo del grupo: 0 no se acepta (antes se guardaba)
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 973000001, N'Dec', N'Setenta', N'Docente', N'Qa', N'qa.dec073.d1@test.local', 1, 1, N'HashBackend_D73');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @d, @idProg, @tvCat, 1, SYSUTCDATETIME());
    DECLARE @g UNIQUEIDENTIFIER = NEWID();
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_grupo @idGrupo = @g, @idAsignatura = @idAsig, @idPeriodoAcademico = @idPeriodo, @codigo = 0,
        @nombre = N'Grupo QA DEC-073', @idDocente = @d, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE 'DBCODE=ERR[_]CODIGO[_]GRUPO[_]INVALIDO|%')
       OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g)
        THROW 53740, 'DEC073_GROUP_CODE_POSITIVE FAILED: codigo 0 debio ser ERR_CODIGO_GRUPO_INVALIDO sin crear el grupo.', 1;
    PRINT 'TEST_PASS:DEC073_GROUP_CODE_POSITIVE';

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uD) THROW 53741, 'TEST FAILED: quedaron datos de prueba.', 1;
    IF @@TRANCOUNT <> 0 THROW 53742, 'TEST FAILED: transaccion abierta.', 1;
    PRINT 'TEST END: test_dec073_validaciones';
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    THROW 53799, @err, 1;
END CATCH
GO
