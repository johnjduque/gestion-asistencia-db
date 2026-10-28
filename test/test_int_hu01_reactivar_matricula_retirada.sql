USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado de SolicitudIngresoGrupo exige QUOTED_IDENTIFIER ON para el DML (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- INT-HU-01 (decision de John 2026-10-28, opcion a): un estudiante retirado del grupo por el docente (HU051,
-- matricula 'I') vuelve a solicitar el ingreso (HU053) y el docente lo acepta (HU055): se REACTIVA la misma
-- matricula (I -> A) en lugar de fallar con 409 por duplicado. El cupo se respeta y una matricula ACTIVA sigue
-- impidiendo una nueva solicitud. Fixtures dentro de UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_int_hu01_reactivar_matricula_retirada';

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;
SELECT TOP 1 @group = g.id, @teacher = g.docente, @periodo = g.periodoAcademico FROM dbo.Grupo g ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion ORDER BY id;
IF @group IS NULL OR @userT IS NULL OR @tipoCC IS NULL
    THROW 54200, 'TEST FAILED: INT_HU01 fixture missing (seed data).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @msg NVARCHAR(4000);
DECLARE @zona NVARCHAR(100) = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
DECLARE @u1 UNIQUEIDENTIFIER = NEWID(), @u2 UNIQUEIDENTIFIER = NEWID(), @e1 UNIQUEIDENTIFIER = NEWID(), @e2 UNIQUEIDENTIFIER = NEWID();
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID(), @s3 UNIQUEIDENTIFIER = NEWID(), @s4 UNIQUEIDENTIFIER = NEWID();
DECLARE @egOriginal UNIQUEIDENTIFIER;

CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #rx (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, codigoEstadoResultante CHAR(1));

BEGIN TRANSACTION;
BEGIN TRY
    -- Periodo vigente y exactamente UN cupo libre.
    UPDATE dbo.PeriodoAcademico SET fechaFin = DATEADD(DAY, 30, @hoyLocal) WHERE id = @periodo;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo
        WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') + 1 WHERE id = @group;

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@u1, @tipoCC, 970009001, N'Uno', N'Qa', N'Est', N'Int', N'qa.inthu01.1@test.local', 1, 1, N'HashBackend_R1'),
           (@u2, @tipoCC, 970009002, N'Dos', N'Qa', N'Est', N'Int', N'qa.inthu01.2@test.local', 1, 1, N'HashBackend_R1');
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e1, @u1), (@e2, @u2);

    -- E1 solicita, el docente acepta (matricula nueva por el interno) y luego lo retira (HU051: A -> I).
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s1, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u1;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s1, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @egOriginal = id FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e1;
    INSERT INTO #r EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = @group, @idEstudiante = @e1, @motivo = N'Retiro QA', @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF @egOriginal IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e1 AND codigoEstadoEstudiante = 'I')
        THROW 54201, 'TEST FAILED: INT_HU01 precondicion (matricula retirada I).', 1;

    -- RM-01: E1 vuelve a solicitar y el docente acepta => se REACTIVA la misma matricula (A), sin duplicar filas.
    TRUNCATE TABLE #r; TRUNCATE TABLE #rx;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s2, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u1;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s2, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_011';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'A' AND mensajeUsuarioResultado = @msg)
        THROW 54202, 'TEST FAILED: RM-01 aceptar a un retirado debe responder SIG_011 (A), no 409.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @group AND estudiante = @e1) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND idEstudiante = @e1 AND codigoEstadoEstudiante = 'A')
       OR (SELECT estudianteGrupo FROM dbo.SolicitudIngresoGrupo WHERE id = @s2) <> @egOriginal
        THROW 54203, 'TEST FAILED: RM-01 se esperaba la MISMA matricula reactivada y enlazada a la solicitud.', 1;
    PRINT 'TEST_PASS:INT_HU01_RM01_REACTIVA_MATRICULA';

    -- RM-02: el cupo se respeta: el grupo quedo lleno, otra solicitud aceptada pasa a lista de espera (E).
    TRUNCATE TABLE #r; TRUNCATE TABLE #rx;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s3, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u2;
    INSERT INTO #rx EXEC dbo.usp_resolver_solicitud_ingreso_grupo @idSolicitud = @s3, @accion = N'ACEPTAR', @motivo = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    IF NOT EXISTS (SELECT 1 FROM #rx WHERE estadoResultado = 1 AND codigoEstadoResultante = 'E')
        THROW 54204, 'TEST FAILED: RM-02 sin cupo la solicitud debe quedar EN ESPERA.', 1;
    PRINT 'TEST_PASS:INT_HU01_RM02_CUPO_RESPETADO';

    -- RM-03: con matricula ACTIVA, E1 no puede volver a solicitar (SIG_004, sin cambios).
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_registrar_solicitud_ingreso_grupo @idSolicitud = @s4, @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @u1;
    SELECT @msg = contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SIG_004';
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msg)
        THROW 54205, 'TEST FAILED: RM-03 matricula activa duplicada debe seguir rechazandose (SIG_004).', 1;
    PRINT 'TEST_PASS:INT_HU01_RM03_ACTIVA_SIGUE_BLOQUEADA';

    IF @@TRANCOUNT <> 1 THROW 54298, 'TEST FAILED: el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 54299, 'TEST FAILED: test_int_hu01_reactivar_matricula_retirada dejo transacciones abiertas.', 1;
DROP TABLE IF EXISTS #r;
DROP TABLE IF EXISTS #rx;
PRINT 'TEST END: test_int_hu01_reactivar_matricula_retirada';
GO
