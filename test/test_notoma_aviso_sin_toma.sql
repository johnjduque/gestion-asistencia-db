USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- NOTOMA-001 (AsistenciasUCO-Infra/docs/work-items/NOTOMA-001-aviso-coordinador-sesion-sin-toma): aviso a la coordinacion cuando el docente no tomo asistencia.
--   NOTOMA_00_OBJETOS               tabla AvisoSesionSinToma, parametros AVISO_SESION_SIN_TOMA (no editables), plantilla con 8 marcadores y los 3 SP con EXECUTE para el rol runtime.
--   NOTOMA_01_PENDIENTES            solo la sesion terminada sin tomas; no entran con tomas, canceladas, en curso, dentro del margen de cierre, mas antiguas que el atraso,
--                                   ya avisadas ni con solicitud pendiente; el lote limita.
--   NOTOMA_02_DESTINATARIOS         DEC-077: el coordinador del programa responsable del grupo compartido, una fila; sin inactivos ni sin correo; 0 filas si la sesion ya no aplica.
--   NOTOMA_03_REGISTRAR_IDEMPOTENTE la marca se escribe una vez; la segunda llamada es exito sin escritura; la sesion sale de las pendientes.
--   NOTOMA_04_SESION_INEXISTENTE    registrar una sesion inexistente responde SES_001 y un total negativo GEN_002, sin escribir.
--   NOTOMA_05_HABILITADO_FALSE      con HABILITADO = false no hay sesiones pendientes.
--   NOTOMA_06_ATRASO_MAXIMO         HORAS_MAXIMAS_ATRASO acota: una sesion de hace 30 h solo entra al ampliar el parametro.
--   NOTOMA_07_SIN_ESTUDIANTES       un grupo sin estudiantes activos (matricula activa y usuario activo) no se selecciona ni se marca; al llegar uno, se avisa.
--   NOTOMA_08_DOCENTE_INACTIVO      la sesion de un docente con usuario inactivo no se selecciona ni se marca; al reactivarlo, se avisa.
--   NOTOMA_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_notoma_aviso_sin_toma';

IF OBJECT_ID(N'dbo.AvisoSesionSinToma', N'U') IS NULL
   OR COL_LENGTH(N'dbo.AvisoSesionSinToma', N'totalCoordinadoresAvisados') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_SESION_SIN_TOMA' AND clave IN ('HABILITADO', 'LOTE', 'HORAS_MAXIMAS_ATRASO')) <> 3
   OR dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'LOTE') <> 50
   OR dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'HORAS_MAXIMAS_ATRASO') <> 24
   OR LOWER(CAST(dbo.ufn_obtener_parametro('AVISO_SESION_SIN_TOMA', 'HABILITADO') AS NVARCHAR(10))) <> N'true'
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE p.grupo = 'AVISO_SESION_SIN_TOMA' AND e.esEditable = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR' AND idioma = 'es' AND version = 1 AND activa = 1
                  AND asunto = N'Sesión sin toma de asistencia: {asignatura} ({fecha})' AND cuerpo LIKE N'%{docente}%{asignatura}%{grupo}%{enlaceSesiones}%')
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR'
       AND marcador IN ('coordinador', 'asignatura', 'grupo', 'fecha', 'horaInicio', 'horaFin', 'docente', 'enlaceSesiones')) <> 8
   OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_sesiones_pendientes_aviso_sin_toma'), (N'usp_consultar_destinatarios_aviso_sin_toma'), (N'usp_registrar_aviso_sesion_sin_toma')) s(nombre)
              WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                                WHERE dp.major_id = OBJECT_ID(N'dbo.' + s.nombre, N'P') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
                                  AND pr.name = N'rol_asistencias_runtime'))
    THROW 59500, 'TEST FAILED NOTOMA_00_OBJETOS: faltan la tabla, los parametros (no editables), la plantilla con 8 marcadores o los permisos de los 3 SP del aviso de sesion sin toma.', 1;
PRINT 'TEST_PASS:NOTOMA_00_OBJETOS';
GO

DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @tipoCancelacion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @estPendiente UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoSolicitudSesion WHERE esFinal = 0);
IF @modoManual IS NULL OR @estCerrada IS NULL OR @tipoCancelacion IS NULL OR @estPendiente IS NULL
    THROW 59501, 'TEST FAILED NOTOMA_: faltan fixtures del seed (modo manual, estado de toma cerrada, tipo de cancelacion, estado de solicitud pendiente).', 1;

CREATE TABLE #ntP (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, fechaHoraFinUtc DATETIME2(7));
CREATE TABLE #ntD (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300),
    nombreDocente NVARCHAR(400), fechaHoraInicioUtc DATETIME2(7), fechaHoraFinUtc DATETIME2(7), idUsuarioCoordinador UNIQUEIDENTIFIER,
    nombreCoordinador NVARCHAR(400), correoCoordinador NVARCHAR(320));
CREATE TABLE #ntR (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT);

DECLARE @corr UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    -- DEC-077: el aviso va solo al coordinador del programa responsable del grupo (aqui B, para probar inactivo y sin correo).
    UPDATE dbo.Grupo SET programaResponsable = @progB WHERE id = @grupoG;
    -- Grupo mixto @grupoG (programas A y B, coordinadores @uCA y @uCB, titular @uT). Sesiones UTC_V2:
    --   S1 terminada hace 30 min sin tomas (pendiente); S2 terminada con una toma cerrada; S3 terminada hace 30 h; S4 cancelada; S5 en curso;
    --   S6 ya avisada; S7 con solicitud pendiente; S8 terminada hace 10 min (entra con margen 0; sale con margen 30)
    DECLARE @s TABLE (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, inicio DATETIME2(7), fin DATETIME2(7));
    INSERT INTO @s (n, id, inicio, fin) VALUES
        (1, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (2, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (3, NEWID(), DATEADD(MINUTE, -1950, SYSUTCDATETIME()), DATEADD(MINUTE, -1830, SYSUTCDATETIME())),
        (4, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (5, NEWID(), DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME())),
        (6, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (7, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (8, NEWID(), DATEADD(MINUTE, -130, SYSUTCDATETIME()), DATEADD(MINUTE, -10, SYSUTCDATETIME()));
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'NOTOMA S', s.n), 700 + s.n, CONCAT(N'NT', s.n), 1, @grupoG, s.inicio, s.fin, N'UTC_V2' FROM @s s;
    DECLARE @s1 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 1), @s2 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 2), @s3 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 3);
    DECLARE @s4 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 4), @s6 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 6), @s7 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 7);
    DECLARE @s8 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 8);

    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, 1, @modoManual, @estCerrada, 0, @docT, CAST(s.inicio AS DATETIME2(0)), CAST(DATEADD(MINUTE, 10, s.inicio) AS DATETIME2(0)), NEWID()
    FROM @s s WHERE s.n = 2;
    INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, usuarioEjecutor, idCorrelacion) VALUES (@s4, @tipoCancelacion, N'NOTOMA cancelada', @uT, NEWID());
    INSERT INTO dbo.AvisoSesionSinToma (sesion, fechaAvisoUtc, totalCoordinadoresAvisados, idCorrelacion) VALUES (@s6, SYSUTCDATETIME(), 1, NEWID());
    INSERT INTO dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, idCorrelacion) VALUES (@s7, @estPendiente, @uT, NEWID());

    -- --------------------------------------------------------------------------------------------------------
    -- 01: sesiones pendientes (margen de cierre en 0 por defecto)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s1 AND idGrupo = @grupoG AND fechaHoraFinUtc = (SELECT fin FROM @s WHERE n = 1))
       OR NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s8)
       OR EXISTS (SELECT 1 FROM #ntP WHERE idGrupo = @grupoG AND idSesion NOT IN (@s1, @s8))
        THROW 59510, 'TEST FAILED NOTOMA_01_PENDIENTES: solo S1 y S8 (terminadas, sin tomas, no canceladas, dentro del atraso, sin aviso ni solicitud pendiente) deben salir; no con toma, la de hace 30 h, la cancelada, la en curso, la avisada ni la de solicitud pendiente.', 1;
    IF (SELECT TOP 1 idSesion FROM #ntP WHERE idGrupo = @grupoG ORDER BY fechaHoraFinUtc ASC) <> @s1
        THROW 59511, 'TEST FAILED NOTOMA_01_PENDIENTES: el orden es por fecha de fin ascendente (S1 antes que S8).', 1;
    TRUNCATE TABLE #ntP;
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 1;
    IF (SELECT COUNT(*) FROM #ntP) > 1
        THROW 59512, 'TEST FAILED NOTOMA_01_PENDIENTES: @tamanoLote = 1 devuelve a lo sumo una sesion.', 1;
    TRUNCATE TABLE #ntP;
    -- margen de cierre en 30 min: S8 (termino hace 10 min) aun tiene la ventana abierta
    DECLARE @margenAntes NVARCHAR(100) = (SELECT valor FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS');
    UPDATE dbo.CatalogoParametro SET valor = N'30' WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS';
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s8) OR NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s1)
        THROW 59513, 'TEST FAILED NOTOMA_01_PENDIENTES: con MARGEN_RETARDO_MINUTOS = 30 la sesion que termino hace 10 min sigue con la ventana abierta y no se avisa.', 1;
    TRUNCATE TABLE #ntP;
    UPDATE dbo.CatalogoParametro SET valor = @margenAntes WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS';
    PRINT 'TEST_PASS:NOTOMA_01_PENDIENTES';

    -- --------------------------------------------------------------------------------------------------------
    -- 02: destinatarios de S1 (DEC-077: solo el coordinador de B, programa responsable)
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #ntD) <> 1
       OR EXISTS (SELECT 1 FROM #ntD WHERE idUsuarioCoordinador = @uCA) OR NOT EXISTS (SELECT 1 FROM #ntD WHERE idUsuarioCoordinador = @uCB)
       OR EXISTS (SELECT 1 FROM #ntD WHERE idSesion <> @s1 OR idGrupo <> @grupoG OR correoCoordinador IS NULL OR nombreCoordinador IS NULL OR nombreAsignatura IS NULL
                  OR nombreGrupo IS NULL OR nombreDocente IS NULL OR idAsignatura <> @asigOPT
                  OR fechaHoraFinUtc <> (SELECT fin FROM @s WHERE n = 1) OR fechaHoraInicioUtc <> (SELECT inicio FROM @s WHERE n = 1))
        THROW 59520, 'TEST FAILED NOTOMA_02_DESTINATARIOS: el grupo compartido avisa solo al coordinador responsable (B) con los datos de la sesion.', 1;
    TRUNCATE TABLE #ntD;
    -- un coordinador de los dos programas es UNA fila
    DECLARE @coordCA UNIQUEIDENTIFIER = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCA);
    DECLARE @coordCB UNIQUEIDENTIFIER = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCB);
    UPDATE dbo.Programa SET coordinador = @coordCA WHERE id = @progB;
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #ntD) <> 1 OR NOT EXISTS (SELECT 1 FROM #ntD WHERE idUsuarioCoordinador = @uCA)
        THROW 59521, 'TEST FAILED NOTOMA_02_DESTINATARIOS: un coordinador de dos programas recibe un solo aviso.', 1;
    TRUNCATE TABLE #ntD;
    -- coordinador inactivo y coordinador con correo vacio se omiten
    UPDATE dbo.Programa SET coordinador = @coordCB WHERE id = @progB;
    UPDATE dbo.Coordinador SET estado = 0 WHERE id = @coordCB;
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #ntD) <> 0
        THROW 59522, 'TEST FAILED NOTOMA_02_DESTINATARIOS: un coordinador inactivo no es destinatario.', 1;
    TRUNCATE TABLE #ntD;
    UPDATE dbo.Coordinador SET estado = 1 WHERE id = @coordCB;
    UPDATE dbo.Usuario SET correo = N'' WHERE id = @uCB;
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #ntD) <> 0
        THROW 59523, 'TEST FAILED NOTOMA_02_DESTINATARIOS: un coordinador con correo vacio no es destinatario.', 1;
    TRUNCATE TABLE #ntD;
    -- la sesion con toma, la cancelada y una inexistente no tienen destinatarios
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s2, @idCorrelacion = @corr;
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @s4, @idCorrelacion = @corr;
    INSERT INTO #ntD EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @corr, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #ntD)
        THROW 59524, 'TEST FAILED NOTOMA_02_DESTINATARIOS: una sesion con toma, cancelada o inexistente devuelve 0 filas.', 1;
    TRUNCATE TABLE #ntD;
    PRINT 'TEST_PASS:NOTOMA_02_DESTINATARIOS';

    -- --------------------------------------------------------------------------------------------------------
    -- 03: registrar es idempotente y saca la sesion de las pendientes
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ntR EXEC dbo.usp_registrar_aviso_sesion_sin_toma @idSesion = @s1, @totalCoordinadoresAvisados = 2, @idCorrelacion = @corr;
    DECLARE @fechaAviso DATETIME2(3) = (SELECT fechaAvisoUtc FROM dbo.AvisoSesionSinToma WHERE sesion = @s1);
    IF NOT EXISTS (SELECT 1 FROM #ntR WHERE estado = 1 AND idCorrelacion = @corr) OR @fechaAviso IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @s1 AND totalCoordinadoresAvisados = 2 AND idCorrelacion = @corr)
        THROW 59530, 'TEST FAILED NOTOMA_03_REGISTRAR_IDEMPOTENTE: la primera llamada escribe la marca con el total y la correlacion.', 1;
    TRUNCATE TABLE #ntR;
    INSERT INTO #ntR EXEC dbo.usp_registrar_aviso_sesion_sin_toma @idSesion = @s1, @totalCoordinadoresAvisados = 5, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ntR WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @s1 AND totalCoordinadoresAvisados = 2 AND fechaAvisoUtc = @fechaAviso)
       OR (SELECT COUNT(*) FROM dbo.AvisoSesionSinToma WHERE sesion = @s1) <> 1
        THROW 59531, 'TEST FAILED NOTOMA_03_REGISTRAR_IDEMPOTENTE: la segunda llamada es exito sin escritura (el total y la fecha no cambian).', 1;
    TRUNCATE TABLE #ntR;
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s1) OR NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s8)
        THROW 59532, 'TEST FAILED NOTOMA_03_REGISTRAR_IDEMPOTENTE: una sesion avisada no vuelve a salir como pendiente (S8 si).', 1;
    TRUNCATE TABLE #ntP;
    PRINT 'TEST_PASS:NOTOMA_03_REGISTRAR_IDEMPOTENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- 04: sesion inexistente y total negativo
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ntR EXEC dbo.usp_registrar_aviso_sesion_sin_toma @idSesion = @corr, @totalCoordinadoresAvisados = 1, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ntR WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]001|%') OR EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @corr)
        THROW 59540, 'TEST FAILED NOTOMA_04_SESION_INEXISTENTE: una sesion inexistente responde SES_001 sin escribir.', 1;
    TRUNCATE TABLE #ntR;
    INSERT INTO #ntR EXEC dbo.usp_registrar_aviso_sesion_sin_toma @idSesion = @s8, @totalCoordinadoresAvisados = -1, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ntR WHERE estado = 0 AND mt LIKE N'DBCODE=GEN[_]002|%') OR EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @s8)
        THROW 59541, 'TEST FAILED NOTOMA_04_SESION_INEXISTENTE: un total negativo responde GEN_002 sin escribir.', 1;
    TRUNCATE TABLE #ntR;
    PRINT 'TEST_PASS:NOTOMA_04_SESION_INEXISTENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- 07: un grupo sin estudiantes activos no se avisa y NO se marca (si recibe estudiantes dentro del atraso, se avisa)
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @gSinEst UNIQUEIDENTIFIER = NEWID(), @sSinEst UNIQUEIDENTIFIER = NEWID();
    DECLARE @estNoA UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo <> N'A' ORDER BY codigo);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@gSinEst, @asigOPT, @periodo, @codGrupo + 10, N'NOTOMA grupo sin estudiantes', 30, 0, 0, 0, @docT);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sSinEst, N'NOTOMA S9', 709, N'NT9', 1, @gSinEst, DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME()), N'UTC_V2');
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sSinEst) OR NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s8)
        THROW 59570, 'TEST FAILED NOTOMA_07_SIN_ESTUDIANTES: la sesion de un grupo sin ninguna matricula no es pendiente (S8 si).', 1;
    TRUNCATE TABLE #ntP;
    -- matricula no activa: sigue excluida
    DECLARE @egSinEst UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@egSinEst, @estNoA, @e0, @gSinEst);
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sSinEst)
        THROW 59571, 'TEST FAILED NOTOMA_07_SIN_ESTUDIANTES: una matricula no activa no cuenta como estudiante activo.', 1;
    TRUNCATE TABLE #ntP;
    -- matricula activa pero usuario inactivo: sigue excluida
    UPDATE dbo.EstudianteGrupo SET estado = @estA WHERE id = @egSinEst;
    DECLARE @uE0Estado BIT = (SELECT estado FROM dbo.Usuario WHERE id = @uE0);
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @uE0;
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sSinEst)
        THROW 59572, 'TEST FAILED NOTOMA_07_SIN_ESTUDIANTES: un estudiante con usuario inactivo no cuenta como estudiante activo.', 1;
    TRUNCATE TABLE #ntP;
    IF EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @sSinEst)
        THROW 59573, 'TEST FAILED NOTOMA_07_SIN_ESTUDIANTES: la exclusion no debe crear marca de aviso.', 1;
    -- el estudiante activo llega dentro del atraso: la sesion se avisa
    UPDATE dbo.Usuario SET estado = @uE0Estado WHERE id = @uE0;
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sSinEst)
        THROW 59574, 'TEST FAILED NOTOMA_07_SIN_ESTUDIANTES: con un estudiante activo (matricula activa y usuario activo) la sesion vuelve a ser pendiente.', 1;
    TRUNCATE TABLE #ntP;
    PRINT 'TEST_PASS:NOTOMA_07_SIN_ESTUDIANTES';

    -- --------------------------------------------------------------------------------------------------------
    -- 08: un docente inactivo no se avisa y NO se marca (si se reactiva dentro del atraso, se avisa)
    -- --------------------------------------------------------------------------------------------------------
    DECLARE @uDI UNIQUEIDENTIFIER = NEWID(), @docI UNIQUEIDENTIFIER = NEWID(), @gDocI UNIQUEIDENTIFIER = NEWID(), @sDocI UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uDI, @tipoCC, 989000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Inactivo', N'Notoma', N'Doc', N'I', CONCAT(N'notoma.di.', LEFT(CONVERT(NVARCHAR(36), @uDI), 8), N'@test.local'), 1, 0);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@docI, @uDI);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@gDocI, @asigOPT, @periodo, @codGrupo + 11, N'NOTOMA grupo docente inactivo', 30, 0, 0, 0, @docI);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (NEWID(), @estA, @e0, @gDocI);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sDocI, N'NOTOMA S10', 710, N'NT10', 1, @gDocI, DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME()), N'UTC_V2');
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sDocI) OR EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma WHERE sesion = @sDocI)
        THROW 59580, 'TEST FAILED NOTOMA_08_DOCENTE_INACTIVO: la sesion de un docente inactivo no es pendiente y no se marca.', 1;
    TRUNCATE TABLE #ntP;
    UPDATE dbo.Usuario SET estado = 1 WHERE id = @uDI;
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @sDocI)
        THROW 59581, 'TEST FAILED NOTOMA_08_DOCENTE_INACTIVO: al reactivar al docente la sesion vuelve a ser pendiente.', 1;
    TRUNCATE TABLE #ntP;
    PRINT 'TEST_PASS:NOTOMA_08_DOCENTE_INACTIVO';

    -- --------------------------------------------------------------------------------------------------------
    -- 06 (antes de 05 para no repetir el reinicio): HORAS_MAXIMAS_ATRASO acota la antiguedad
    -- --------------------------------------------------------------------------------------------------------
    DELETE FROM dbo.AvisoSesionSinToma WHERE sesion = @s1;
    UPDATE dbo.CatalogoParametro SET valor = N'48' WHERE grupo = 'AVISO_SESION_SIN_TOMA' AND clave = 'HORAS_MAXIMAS_ATRASO';
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s3) OR NOT EXISTS (SELECT 1 FROM #ntP WHERE idSesion = @s1)
        THROW 59560, 'TEST FAILED NOTOMA_06_ATRASO_MAXIMO: con HORAS_MAXIMAS_ATRASO = 48 la sesion de hace 30 h tambien es pendiente.', 1;
    TRUNCATE TABLE #ntP;
    PRINT 'TEST_PASS:NOTOMA_06_ATRASO_MAXIMO';

    -- --------------------------------------------------------------------------------------------------------
    -- 05: HABILITADO = false => 0 filas
    -- --------------------------------------------------------------------------------------------------------
    UPDATE dbo.CatalogoParametro SET valor = N'false' WHERE grupo = 'AVISO_SESION_SIN_TOMA' AND clave = 'HABILITADO';
    INSERT INTO #ntP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ntP)
        THROW 59550, 'TEST FAILED NOTOMA_05_HABILITADO_FALSE: con HABILITADO = false no hay sesiones pendientes.', 1;
    TRUNCATE TABLE #ntP;
    PRINT 'TEST_PASS:NOTOMA_05_HABILITADO_FALSE';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 59598, 'TEST FAILED NOTOMA_TRANCOUNT_ZERO: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:NOTOMA_TRANCOUNT_ZERO';
PRINT 'TEST END: test_notoma_aviso_sin_toma';
GO
