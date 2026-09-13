USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id
FROM dbo.uv_estudiante_grupo eg
JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @reason UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'A');
IF @group IS NULL OR @student IS NULL OR @enrollment IS NULL OR @reason IS NULL
    THROW 51800, 'TEST FAILED: ATTENDANCE fixture missing.', 1;

DECLARE @sessionBulk UNIQUEIDENTIFIER = NEWID(), @sessionAuto UNIQUEIDENTIFIER = NEWID(), @sessionSingle UNIQUEIDENTIFIER = NEWID();
DECLARE @codeBulk NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @codeAuto NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @codeSingle NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @firstNumber INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
CREATE TABLE #attendanceResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES
        (@sessionBulk, N'QA Bulk', @firstNumber, @codeBulk, 1, @group, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE())),
        (@sessionAuto, N'QA Auto', @firstNumber + 1, @codeAuto, 1, @group, DATEADD(HOUR, 3, GETDATE()), DATEADD(HOUR, 4, GETDATE())),
        (@sessionSingle, N'QA Single', @firstNumber + 2, @codeSingle, 1, @group, DATEADD(HOUR, 5, GETDATE()), DATEADD(HOUR, 6, GETDATE()));

    DECLARE @json NVARCHAR(MAX) = CONCAT(N'[{"idEstudiante":"', CONVERT(NVARCHAR(36), @student), N'","estado":"A"}]');
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'BloqueAsistenciasSesion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @sessionBulk, @asistenciaJSON = @json, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51801, 'TEST FAILED: ATTENDANCE_BULK_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionBulk AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason)
        THROW 51802, 'TEST FAILED: ATTENDANCE_BULK_SUCCESS did not persist visible attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    DECLARE @missingSession UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @missingSession,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencias_sesion @idSesion = @missingSession, @asistenciaJSON = @json, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51803, 'TEST FAILED: ATTENDANCE_BULK_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @missingSession)
        THROW 51804, 'TEST FAILED: ATTENDANCE_BULK_INVALID wrote attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'AsistenciaEstudianteAutonomo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sessionAuto, @codigoVerificacion = @codeAuto, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51805, 'TEST FAILED: ATTENDANCE_AUTO_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionAuto AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason)
        THROW 51806, 'TEST FAILED: ATTENDANCE_AUTO_SUCCESS did not persist visible attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_007', @p_param1 = 'codigoVerificacion',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante_autonomo
        @idEstudiante = @student, @idSesion = @sessionSingle, @codigoVerificacion = N'BAD', @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51807, 'TEST FAILED: ATTENDANCE_AUTO_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @sessionSingle)
        THROW 51808, 'TEST FAILED: ATTENDANCE_AUTO_INVALID wrote attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'AsistenciaEstudiante',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante
        @idEstudianteGrupo = @enrollment, @idGrupoSesion = @sessionSingle, @idEstadoAsistencia = @reason, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51809, 'TEST FAILED: ATTENDANCE_SINGLE_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia a JOIN dbo.uv_detalle_asistencia d ON d.idAsistencia = a.id
        WHERE a.idSesion = @sessionSingle AND a.idEstudianteGrupo = @enrollment AND d.asistio = 1 AND d.idRazonCausa = @reason)
        THROW 51810, 'TEST FAILED: ATTENDANCE_SINGLE_SUCCESS did not persist visible attendance.', 1;

    TRUNCATE TABLE #attendanceResult;
    DECLARE @missingEnrollment UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_001', @p_param1 = 'EstudianteGrupo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #attendanceResult
    EXEC dbo.usp_registrar_asistencia_estudiante
        @idEstudianteGrupo = @missingEnrollment, @idGrupoSesion = @sessionSingle,
        @idEstadoAsistencia = @reason, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #attendanceResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51811, 'TEST FAILED: ATTENDANCE_SINGLE_INVALID wrong canonical result.', 1;
    IF (SELECT COUNT(*) FROM dbo.Asistencia WHERE sesion = @sessionSingle) <> 1
        THROW 51812, 'TEST FAILED: ATTENDANCE_SINGLE_INVALID changed existing attendance.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id IN (@sessionBulk, @sessionAuto, @sessionSingle))
    THROW 51813, 'TEST FAILED: ATTENDANCE leaked sessions.', 1;
IF EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion IN (@sessionBulk, @sessionAuto, @sessionSingle))
    THROW 51814, 'TEST FAILED: ATTENDANCE leaked rows.', 1;
IF @@TRANCOUNT <> 0 THROW 51815, 'TEST FAILED: ATTENDANCE left transaction open.', 1;
PRINT 'TEST_PASS:ATTENDANCE_BULK_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_BULK_INVALID';
PRINT 'TEST_PASS:ATTENDANCE_AUTO_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_AUTO_INVALID';
PRINT 'TEST_PASS:ATTENDANCE_SINGLE_SUCCESS';
PRINT 'TEST_PASS:ATTENDANCE_SINGLE_INVALID';
PRINT 'TEST END: test_attendance_commands';
GO
