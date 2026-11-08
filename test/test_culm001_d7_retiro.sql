USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ============================================================================
-- CULM-001 D.7 (CONTRACT D §8, TD-009, HU027): retiro del registro individual autonomo.
--   D7-01  usp_registrar_asistencia_estudiante_autonomo ya no existe (OBJECT_ID IS NULL) y ningun modulo lo referencia
--   D7-02  ningun principal conserva permisos sobre el SP retirado (sys.database_permissions)
--   D7-05  el lote congelado y el registro por toma/token de B.2 siguen y conservan EXECUTE para el rol runtime
--   D7-04  registro por token con la toma abierta y la ventana de la sesion ya vencida -> SES_008 y sin escritura
-- (D7-03, up -> down -> up de la migracion 26, esta en test_culm001_d7_migraciones.sql y lo corre test_culm001_d7.ps1.)
-- ============================================================================
PRINT 'TEST START: test_culm001_d7_retiro (CULM-001 D.7, HU027, TD-009)';

IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
    THROW 57900, 'TEST FAILED CULM001_D7_01: usp_registrar_asistencia_estudiante_autonomo sigue existiendo.', 1;
IF EXISTS (SELECT 1 FROM sys.sql_modules m WHERE m.definition LIKE N'%usp[_]registrar[_]asistencia[_]estudiante[_]autonomo%')
    THROW 57901, 'TEST FAILED CULM001_D7_01: un modulo de la BD aun referencia el SP autonomo retirado.', 1;
PRINT 'TEST_PASS:CULM001_D7_01_SP_RETIRADO';

IF EXISTS (SELECT 1 FROM sys.database_permissions dp
           WHERE dp.class = 1 AND OBJECT_NAME(dp.major_id) = N'usp_registrar_asistencia_estudiante_autonomo')
    THROW 57902, 'TEST FAILED CULM001_D7_02: quedan permisos sobre el SP autonomo retirado.', 1;
PRINT 'TEST_PASS:CULM001_D7_02_SIN_PERMISOS';

IF EXISTS (
    SELECT 1 FROM (VALUES (N'usp_registrar_asistencias_sesion'), (N'usp_registrar_asistencias_toma'), (N'usp_registrar_asistencia_por_token'),
                          (N'usp_abrir_toma_asistencia'), (N'usp_abrir_qr_toma')) o(nombre)
    WHERE OBJECT_ID(N'dbo.' + o.nombre, N'P') IS NULL
       OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                      WHERE dp.major_id = OBJECT_ID(N'dbo.' + o.nombre) AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
                        AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')))
    THROW 57903, 'TEST FAILED CULM001_D7_05: el lote, la toma o el token perdieron el SP o su EXECUTE.', 1;
PRINT 'TEST_PASS:CULM001_D7_05_LOTE_Y_TOMA_INTACTOS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL
    THROW 57910, 'TEST FAILED CULM001_D7_04: faltan fixtures del seed.', 1;

CREATE TABLE #d7A (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
    ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
CREATE TABLE #d7O (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idTokenAsistencia UNIQUEIDENTIFIER NULL, idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL,
    fechaRotacionUtc DATETIME2(0) NULL, fechaExpiracionUtc DATETIME2(0) NULL, rotacionSegundos INT NULL);
CREATE TABLE #d7R (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
    idToma UNIQUEIDENTIFIER NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, nombreAsignatura NVARCHAR(200) NULL,
    nombreGrupo NVARCHAR(300) NULL, numeroSesion INT NULL, numeroToma SMALLINT NULL, yaRegistrado BIT NULL, fechaRegistroUtc DATETIME2(0) NULL);

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @h VARBINARY(32) = HASHBYTES('SHA2_256', CONCAT(N'culmd7-token-', NEWID()));
DECLARE @pin NCHAR(6) = CAST(800000 + ABS(CHECKSUM(NEWID()) % 99999) AS NCHAR(6));

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @uE UNIQUEIDENTIFIER = NEWID(), @e UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 981000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'CulmD', N'Docente', N'D7', CONCAT(N'culmd7.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMD7'),
           (@uE, @tipoCC, 982000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Alumno', N'CulmD', N'Estudiante', N'D7', CONCAT(N'culmd7.e.', @tag, N'@test.local'), 1, 1, N'HashBackend_CULMD7');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e, @uE);
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID(), @eg UNIQUEIDENTIFIER = NEWID(), @s UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'CULMD7 periodo', 3400000 + ABS(CHECKSUM(NEWID()) % 500000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 956000 + ABS(CHECKSUM(NEWID()) % 43999), N'CULMD7 Grupo', 30, 0, 0, 0, @d);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg, @estadoA, @e, @g);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s, N'CULMD7 sesion', 1, N'CD7S01', 1, @g, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2');

    INSERT INTO #d7A EXEC dbo.usp_abrir_toma_asistencia @idSesion = @s, @codigoModo = N'QR', @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    DECLARE @toma UNIQUEIDENTIFIER = (SELECT idToma FROM #d7A WHERE estado = 1 AND codigoModo = N'QR');
    INSERT INTO #d7O EXEC dbo.usp_abrir_qr_toma @idToma = @toma, @tokenHash = @h, @pin = @pin, @idCorrelacion = @corr, @idUsuarioEjecutor = @uD;
    IF @toma IS NULL OR NOT EXISTS (SELECT 1 FROM #d7O WHERE estado = 1)
        THROW 57911, 'TEST FAILED CULM001_D7_04: no se pudo abrir la toma QR del fixture.', 1;

    -- La ventana vence: la toma sigue abierta y el token sin cerrar, pero la sesion termino hace mas que el margen.
    UPDATE dbo.Sesion SET fechaHoraInicio = DATEADD(HOUR, -6, SYSUTCDATETIME()), fechaHoraFin = DATEADD(HOUR, -4, SYSUTCDATETIME()), procedenciaTemporal = N'UTC_V2' WHERE id = @s;
    SET @corr = NEWID();
    INSERT INTO #d7R EXEC dbo.usp_registrar_asistencia_por_token @tokenHash = @h, @idCorrelacion = @corr, @idUsuarioEjecutor = @uE;
    IF NOT EXISTS (SELECT 1 FROM #d7R WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]008|%')
       OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE sesion = @s)
        THROW 57912, 'TEST FAILED CULM001_D7_04: el registro por token con la ventana vencida debe responder SES_008 sin escribir.', 1;
    PRINT 'TEST_PASS:CULM001_D7_04_TOKEN_VENTANA_VENCIDA';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
DROP TABLE #d7A, #d7O, #d7R;
GO

IF @@TRANCOUNT <> 0
    THROW 57999, 'TEST FAILED CULM001_D7: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:CULM001_D7_TRANCOUNT_ZERO';
PRINT 'TEST END: test_culm001_d7_retiro';
GO
