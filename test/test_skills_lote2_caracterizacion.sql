USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 2 (plan por lotes 2026-11-25): renombre usp_internal_* -> usp_*_interno (D3) y robustez (triplete OUTPUT, TRY/CATCH).
-- Fija el comportamiento de los nucleos y SP corregidos en el lote que no tenian prueba directa del rechazo. Lo funcional (tomas,
-- QR, matricula por token, festivos, asignaturas) lo siguen cubriendo sus pruebas de dominio, que ahora llaman a los nombres nuevos.
-- Lo que escribe corre dentro de una transaccion revertida, sobre la fixture de asignatura compartida de B2NM.
--   SKL2_N01_NOMBRES_INTERNOS          los 16 nucleos existen con el nombre nuevo, ninguno con el viejo, ninguno con EXECUTE para el runtime,
--                                      ningun modulo llama a un nombre viejo y los 9 nucleos corregidos tienen el triplete OUTPUT
--   SKL2_R01_RESOLVER_TOKEN_ASISTENCIA usp_resolver_token_asistencia_interno: sin hash ni PIN o con los dos => AQR_007; hash desconocido =>
--                                      AQR_001; los dos con @estadoResultado = 1 y sin ids
--   SKL2_R02_RESOLVER_TOKEN_MATRICULA  usp_resolver_token_matricula_interno: MQR_007 y MQR_001 igual que el anterior
--   SKL2_R03_RESUMEN_SESIONES_DOCENTE  usp_consultar_resumen_sesiones_grupo_docente: 1 fila por sesion (EN_CURSO, 3 activos sin registro)
--   SKL2_R04_RADICAR_V4_SIN_TOMA       usp_radicar_solicitud_revision_asistencia_v4 sin @idToma => GEN_002, estado 0, ids NULL y 0 soportes
--   SKL2_R05_CONTACTO_NOTIFICACION     usp_consultar_contacto_notificacion_interno: solo usuarios activos con UUID valido, sin repetir
--   SKL2_R06_RECHAZOS_LECTURA          (fuera de la transaccion) previsualizar horario sin ejecutor y resumen de sesiones de un grupo ajeno
--                                      siguen rechazandose con THROW 51000 (GEN_002 / mensaje del validador)
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote2_caracterizacion';
DROP TABLE IF EXISTS #skl2Resumen;
DROP TABLE IF EXISTS #skl2Radicar;
DROP TABLE IF EXISTS #skl2Contacto;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @msg NVARCHAR(4000);
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID(), @rechazo VARCHAR(20);
    DECLARE @idTk UNIQUEIDENTIFIER, @idTm UNIQUEIDENTIFIER, @idSe UNIQUEIDENTIFIER, @idGr UNIQUEIDENTIFIER, @idDo UNIQUEIDENTIFIER;

    -- ===================================================================== N01
    DECLARE @nucleos TABLE (nombre SYSNAME NOT NULL PRIMARY KEY, corregido BIT NOT NULL);
    INSERT INTO @nucleos (nombre, corregido) VALUES
        (N'aplicar_festivos_grupo', 0), (N'aplicar_festivos_grupos', 1), (N'asegurar_estudiante_programa_grupo', 1), (N'asociar_asignatura_plan', 1),
        (N'cancelar_sesiones_receso', 0), (N'cargar_dias_festivos', 0), (N'cerrar_toma', 1), (N'marcar_ausentes_toma', 1), (N'matricular_por_token', 0),
        (N'radicar_solicitud_revision', 0), (N'reactivar_matricula_retirada', 0), (N'resolver_token_asistencia', 1), (N'resolver_token_matricula', 1),
        (N'rotar_token_asistencia', 1), (N'rotar_token_matricula', 1), (N'validar_plazo_justificacion', 0);
    SET @msg = (SELECT STRING_AGG(CAST(n.nombre AS NVARCHAR(MAX)), N', ') FROM @nucleos n
                WHERE OBJECT_ID(N'dbo.usp_' + n.nombre + N'_interno', N'P') IS NULL
                   OR OBJECT_ID(N'dbo.usp_internal_' + n.nombre, N'P') IS NOT NULL
                   OR EXISTS (SELECT 1 FROM sys.database_permissions dp
                              WHERE dp.major_id = OBJECT_ID(N'dbo.usp_' + n.nombre + N'_interno') AND dp.permission_name = N'EXECUTE'
                                AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                   OR (n.corregido = 1 AND (SELECT COUNT(*) FROM sys.parameters x
                                            WHERE x.object_id = OBJECT_ID(N'dbo.usp_' + n.nombre + N'_interno') AND x.is_output = 1
                                              AND x.name IN (N'@mensajeUsuarioResultado', N'@mensajeTecnicoResultado', N'@estadoResultado')) <> 3));
    IF @msg IS NOT NULL
       OR EXISTS (SELECT 1 FROM sys.procedures p WHERE p.name LIKE N'usp[_]internal[_]%')
       OR EXISTS (SELECT 1 FROM sys.sql_modules sm WHERE REPLACE(sm.definition, N'antes usp_internal_', N'') LIKE N'%usp[_]internal[_]%')
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: SKL2_N01_NOMBRES_INTERNOS ', @msg);
        THROW 54201, @msg, 1;
    END
    PRINT 'TEST_PASS:SKL2_N01_NOMBRES_INTERNOS';

    -- ===================================================================== R01
    EXEC dbo.usp_resolver_token_asistencia_interno @tokenHash = NULL, @pin = NULL, @idCorrelacion = @corr,
         @idTokenAsistencia = @idTk OUTPUT, @idToma = @idTm OUTPUT, @idSesion = @idSe OUTPUT, @idGrupo = @idGr OUTPUT,
         @codigoRechazo = @rechazo OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @rechazo <> 'AQR_007' OR @idTk IS NOT NULL OR @idTm IS NOT NULL OR @idGr IS NOT NULL
        THROW 54211, 'TEST FAILED: SKL2_R01_RESOLVER_TOKEN_ASISTENCIA (sin hash ni PIN)', 1;
    EXEC dbo.usp_resolver_token_asistencia_interno @tokenHash = 0x01, @pin = N'123456', @idCorrelacion = @corr,
         @idTokenAsistencia = @idTk OUTPUT, @idToma = @idTm OUTPUT, @idSesion = @idSe OUTPUT, @idGrupo = @idGr OUTPUT,
         @codigoRechazo = @rechazo OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @rechazo <> 'AQR_007'
        THROW 54212, 'TEST FAILED: SKL2_R01_RESOLVER_TOKEN_ASISTENCIA (hash y PIN)', 1;
    EXEC dbo.usp_resolver_token_asistencia_interno @tokenHash = 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF, @pin = NULL,
         @idCorrelacion = @corr, @idTokenAsistencia = @idTk OUTPUT, @idToma = @idTm OUTPUT, @idSesion = @idSe OUTPUT, @idGrupo = @idGr OUTPUT,
         @codigoRechazo = @rechazo OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @rechazo <> 'AQR_001' OR @idTk IS NOT NULL OR @idSe IS NOT NULL
        THROW 54213, 'TEST FAILED: SKL2_R01_RESOLVER_TOKEN_ASISTENCIA (hash desconocido)', 1;
    PRINT 'TEST_PASS:SKL2_R01_RESOLVER_TOKEN_ASISTENCIA';

    -- ===================================================================== R02
    EXEC dbo.usp_resolver_token_matricula_interno @tokenHash = NULL, @pin = NULL, @idCorrelacion = @corr,
         @idVentana = @idTk OUTPUT, @idGrupo = @idGr OUTPUT, @idDocenteEmisor = @idDo OUTPUT,
         @codigoRechazo = @rechazo OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @rechazo <> 'MQR_007' OR @idTk IS NOT NULL OR @idGr IS NOT NULL OR @idDo IS NOT NULL
        THROW 54221, 'TEST FAILED: SKL2_R02_RESOLVER_TOKEN_MATRICULA (sin hash ni PIN)', 1;
    EXEC dbo.usp_resolver_token_matricula_interno @tokenHash = NULL, @pin = N'000000', @idCorrelacion = @corr,
         @idVentana = @idTk OUTPUT, @idGrupo = @idGr OUTPUT, @idDocenteEmisor = @idDo OUTPUT,
         @codigoRechazo = @rechazo OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR (@rechazo <> 'MQR_001' AND EXISTS (SELECT 1 FROM dbo.TokenMatriculaGrupo WHERE pin = N'000000' OR pinAnterior = N'000000'))
       OR (@rechazo IS NULL AND @idTk IS NULL)
        THROW 54222, 'TEST FAILED: SKL2_R02_RESOLVER_TOKEN_MATRICULA (PIN desconocido)', 1;
    PRINT 'TEST_PASS:SKL2_R02_RESOLVER_TOKEN_MATRICULA';

    -- ===================================================================== R03
    DECLARE @sesion UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sesion, N'SKL2 en curso', 1, N'SKL2S1', 1, @grupoG, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2');
    CREATE TABLE #skl2Resumen (
        idSesion NVARCHAR(400) NULL, numero NVARCHAR(400) NULL, nombre NVARCHAR(400) NULL, fechaHoraInicio NVARCHAR(400) NULL,
        fechaHoraFin NVARCHAR(400) NULL, procedenciaTemporal NVARCHAR(400) NULL, estadoSesion NVARCHAR(400) NULL, estadoSolicitud NVARCHAR(400) NULL,
        pendienteAprobacion NVARCHAR(400) NULL, totalEstudiantes INT NULL, presentes INT NULL, parciales INT NULL, justificadas INT NULL,
        ausentes INT NULL, sinRegistro INT NULL, sesionesProgramadas INT NULL, sesionesEjecutadas INT NULL, sesionesCanceladas INT NULL,
        sesionesEnCurso INT NULL, idSesionEnCurso NVARCHAR(400) NULL, idSesionProxima NVARCHAR(400) NULL, estudiantesActivos INT NULL,
        estudiantesEnRiesgo INT NULL, promedioAsistencia NVARCHAR(400) NULL, umbralAdvertencia NVARCHAR(400) NULL, umbralPerdida NVARCHAR(400) NULL);
    INSERT INTO #skl2Resumen EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = @uT, @idCorrelacion = @corr, @idGrupo = @grupoG;
    IF (SELECT COUNT(*) FROM #skl2Resumen) <> (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @grupoG)
       OR NOT EXISTS (SELECT 1 FROM #skl2Resumen r
                      WHERE TRY_CONVERT(UNIQUEIDENTIFIER, r.idSesion) = @sesion AND r.estadoSesion = N'EN_CURSO' AND r.presentes = 0
                        AND r.ausentes = 0 AND r.sinRegistro = r.totalEstudiantes AND r.totalEstudiantes = r.estudiantesActivos
                        AND r.sesionesEnCurso >= 1 AND r.estudiantesEnRiesgo IS NOT NULL AND r.estudiantesEnRiesgo >= 0
                        AND r.estudiantesActivos = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo eg
                                                    WHERE eg.idGrupo = @grupoG
                                                      AND eg.codigoEstadoEstudiante = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10))))
        THROW 54231, 'TEST FAILED: SKL2_R03_RESUMEN_SESIONES_DOCENTE', 1;
    PRINT 'TEST_PASS:SKL2_R03_RESUMEN_SESIONES_DOCENTE';

    -- ===================================================================== R04
    CREATE TABLE #skl2Radicar (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NULL,
        idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL, idToma UNIQUEIDENTIFIER NULL);
    INSERT INTO #skl2Radicar EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = @eA, @idSesion = @sesion, @idToma = NULL,
         @categoria = N'SALUD', @justificacion = N'SKL2', @idCorrelacion = @corr, @idUsuarioEjecutor = @uEA;
    IF (SELECT COUNT(*) FROM #skl2Radicar) <> 1
       OR NOT EXISTS (SELECT 1 FROM #skl2Radicar WHERE estado = 0 AND mt LIKE N'%GEN[_]002%' AND idCorrelacion = @corr
                                                   AND idSolicitudRevision IS NULL AND totalSoportes = 0 AND idToma IS NULL)
        THROW 54241, 'TEST FAILED: SKL2_R04_RADICAR_V4_SIN_TOMA', 1;
    PRINT 'TEST_PASS:SKL2_R04_RADICAR_V4_SIN_TOMA';

    -- ===================================================================== R05
    CREATE TABLE #skl2Contacto (idUsuario UNIQUEIDENTIFIER NULL, correo NVARCHAR(400) NULL, correoConfirmado BIT NULL);
    DECLARE @json NVARCHAR(MAX) = CONCAT(N'["', @uCA, N'","', @uCA, N'","no-es-uuid","', NEWID(), N'"]');
    INSERT INTO #skl2Contacto EXEC dbo.usp_consultar_contacto_notificacion_interno @usuariosJson = @json, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR (SELECT COUNT(*) FROM #skl2Contacto) <> 1
       OR NOT EXISTS (SELECT 1 FROM #skl2Contacto c INNER JOIN dbo.Usuario u ON u.id = c.idUsuario WHERE c.idUsuario = @uCA AND c.correo = u.correo)
        THROW 54251, 'TEST FAILED: SKL2_R05_CONTACTO_NOTIFICACION', 1;
    PRINT 'TEST_PASS:SKL2_R05_CONTACTO_NOTIFICACION';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- ===================================================================== R06 (fuera de la transaccion: los SP de lectura usan XACT_ABORT)
DECLARE @errorPrevisualizar INT, @mensajePrevisualizar NVARCHAR(4000), @errorResumen INT;
BEGIN TRY
    EXEC dbo.usp_previsualizar_horario_grupo @horariosJSON = N'[]', @idCorrelacion = '5C2A0000-0000-0000-0000-0000000000A1', @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SELECT @errorPrevisualizar = ERROR_NUMBER(), @mensajePrevisualizar = ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    EXEC dbo.usp_consultar_resumen_sesiones_grupo_docente @idUsuarioEjecutor = '5C2A0000-0000-0000-0000-0000000000A2',
         @idCorrelacion = '5C2A0000-0000-0000-0000-0000000000A3', @idGrupo = '5C2A0000-0000-0000-0000-0000000000A4';
END TRY
BEGIN CATCH
    SET @errorResumen = ERROR_NUMBER();
END CATCH;
IF @errorPrevisualizar IS NULL OR @errorPrevisualizar <> 51000 OR @mensajePrevisualizar NOT LIKE N'%GEN[_]002%'
   OR @errorResumen IS NULL OR @errorResumen <> 51000 OR @@TRANCOUNT <> 0
    THROW 54261, 'TEST FAILED: SKL2_R06_RECHAZOS_LECTURA', 1;
PRINT 'TEST_PASS:SKL2_R06_RECHAZOS_LECTURA';
IF @@TRANCOUNT <> 0
    THROW 54262, 'TEST FAILED: SKL2_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:SKL2_TRANCOUNT_ZERO';
GO
