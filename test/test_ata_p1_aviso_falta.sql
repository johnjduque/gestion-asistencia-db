USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ATA P1 (docs/contracts/ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS.md, seccion C): aviso de falta por sesion, un correo por estudiante y sesion.
--   ATA_P1_C00_OBJETOS             tabla AvisoFaltaSesion, parametros AVISO_FALTA_SESION, plantilla FALTA_ASISTENCIA_SESION_ESTUDIANTE y los 3 SP con EXECUTE para el rol runtime.
--   ATA_P1_C01_SESIONES_PENDIENTES solo la sesion terminada, con tomas cerradas, no cancelada, dentro del atraso maximo y sin aviso previo; el lote limita.
--   ATA_P1_C02_FALTAS_POR_TOMA     una fila por (estudiante con SJC, toma en SJC); sin AN, sin registro ni matricula retirada.
--   ATA_P1_C03_REGISTRAR_IDEMPOTENTE la marca se escribe una vez; la segunda llamada es exito sin escritura; la sesion sale de las pendientes.
--   ATA_P1_C04_SESION_INEXISTENTE  registrar una sesion inexistente responde SES_001 sin escribir.
--   ATA_P1_C05_HABILITADO_FALSE    con HABILITADO = false no hay sesiones pendientes.
--   ATA_P1_C06_ATRASO_MAXIMO       HORAS_MAXIMAS_ATRASO acota: una sesion de hace 30 h solo entra al ampliar el parametro.
--   ATA_P1_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_ata_p1_aviso_falta';

IF OBJECT_ID(N'dbo.AvisoFaltaSesion', N'U') IS NULL
   OR COL_LENGTH(N'dbo.AvisoFaltaSesion', N'totalEstudiantesAvisados') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_FALTA_SESION' AND clave IN ('HABILITADO', 'LOTE', 'HORAS_MAXIMAS_ATRASO')) <> 3
   OR dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'LOTE') <> 50
   OR dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'HORAS_MAXIMAS_ATRASO') <> 24
   OR LOWER(CAST(dbo.ufn_obtener_parametro('AVISO_FALTA_SESION', 'HABILITADO') AS NVARCHAR(10))) <> N'true'
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE p.grupo = 'AVISO_FALTA_SESION' AND e.esEditable = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'FALTA_ASISTENCIA_SESION_ESTUDIANTE' AND idioma = 'es' AND version = 1 AND activa = 1
                  AND asunto = N'Registro de inasistencia: {asignatura} ({fecha})' AND cuerpo LIKE N'%{detalleFaltas}%{fechaLimiteReclamo}%{enlaceReclamo}%')
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'FALTA_ASISTENCIA_SESION_ESTUDIANTE'
       AND marcador IN ('estudiante', 'asignatura', 'grupo', 'fecha', 'horaInicio', 'horaFin', 'detalleFaltas', 'fechaLimiteReclamo', 'enlaceReclamo')) <> 9
   OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_sesiones_pendientes_aviso_falta'), (N'usp_consultar_faltas_sesion_aviso'), (N'usp_registrar_aviso_falta_sesion')) s(nombre)
              WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                                WHERE dp.major_id = OBJECT_ID(N'dbo.' + s.nombre, N'P') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
                                  AND pr.name = N'rol_asistencias_runtime'))
    THROW 59100, 'TEST FAILED ATA_P1_C00_OBJETOS: faltan la tabla, los parametros (no editables), la plantilla con 9 marcadores o los permisos de los 3 SP del aviso de falta por sesion.', 1;
PRINT 'TEST_PASS:ATA_P1_C00_OBJETOS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoNoA UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo <> 'A' ORDER BY codigo);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estAbierta UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 1);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @tipoCancelacion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @estadoNoA IS NULL OR @modoManual IS NULL OR @estAbierta IS NULL
   OR @estCerrada IS NULL OR @tipoCancelacion IS NULL
    THROW 59101, 'TEST FAILED ATA_P1_C: faltan fixtures del seed (asignatura, institucion, estados de matricula y de toma, tipo de cancelacion).', 1;

CREATE TABLE #ataP (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, fechaHoraFinUtc DATETIME2(7));
CREATE TABLE #ataF (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300),
    fechaHoraInicioUtc DATETIME2(7), fechaHoraFinUtc DATETIME2(7), idUsuarioEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), correoEstudiante NVARCHAR(320),
    numeroToma SMALLINT, fechaPuntoControlUtc DATETIME2(7), totalTomasSesion INT, totalTomasEnFalta INT, minutosFalta INT, fechaLimiteReclamoUtc DATETIME2(7));
CREATE TABLE #ataR (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT);

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @n INT;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #ataEst (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER, idAsistencia UNIQUEIDENTIFIER);
    INSERT INTO #ataEst (n, idUsuario, idEstudiante, idEG, idAsistencia) SELECT v.n, NEWID(), NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4),(5)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uD, @tipoCC, 989000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'Aviso', N'Doc', N'P1', CONCAT(N'ata.av.d.', @tag, N'@test.local'), 1, 1);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    SELECT e.idUsuario, @tipoCC, 990000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Aviso', e.n), N'Falta', N'Est', N'P1',
           CONCAT(N'ata.av.e', e.n, N'.', @tag, N'@test.local'), 1, 1
    FROM #ataEst e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #ataEst;
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'ATA periodo aviso', 3970000 + ABS(CHECKSUM(NEWID()) % 20000), DATEADD(DAY, -30, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 969000 + ABS(CHECKSUM(NEWID()) % 4999), N'ATA Grupo aviso', 30, 0, 0, 0, @d);
    -- estudiantes 1..4 activos; el 5 con matricula no activa
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT e.idEG, IIF(e.n = 5, @estadoNoA, @estadoA), e.idEstudiante, @g FROM #ataEst e;

    -- Sesiones: S1 terminada hace 30 min con 3 tomas cerradas (pendiente); S2 terminada con una toma abierta; S3 terminada hace 30 h; S4 cancelada;
    -- S5 sin tomas; S6 ya avisada; S7 en curso
    DECLARE @s TABLE (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, inicio DATETIME2(7), fin DATETIME2(7));
    INSERT INTO @s (n, id, inicio, fin) VALUES
        (1, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (2, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (3, NEWID(), DATEADD(MINUTE, -1950, SYSUTCDATETIME()), DATEADD(MINUTE, -1830, SYSUTCDATETIME())),
        (4, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (5, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (6, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME())),
        (7, NEWID(), DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()));
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'ATA aviso S', s.n), s.n, CONCAT(N'AV', s.n, N'-', @tag), 1, @g, s.inicio, s.fin, N'UTC_V2' FROM @s s;
    DECLARE @s1 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 1), @s2 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 2), @s3 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 3);
    DECLARE @s4 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 4), @s5 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 5), @s6 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 6);

    -- Tomas: S1, S3, S4, S6 con 3 tomas cerradas (minutos 0, 40 y 80 desde el inicio); S2 con la 3 abierta
    DECLARE @t TABLE (idSesion UNIQUEIDENTIFIER, numero SMALLINT, idToma UNIQUEIDENTIFIER, PRIMARY KEY (idSesion, numero));
    INSERT INTO @t (idSesion, numero, idToma) SELECT s.id, v.numero, NEWID() FROM @s s CROSS JOIN (VALUES (1), (2), (3)) v(numero) WHERE s.n IN (1, 2, 3, 4, 6);
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT t.idToma, t.idSesion, t.numero, @modoManual, IIF(s.n = 2 AND t.numero = 3, @estAbierta, @estCerrada), 0, @d,
           CAST(DATEADD(MINUTE, (t.numero - 1) * 40, s.inicio) AS DATETIME2(0)),
           IIF(s.n = 2 AND t.numero = 3, NULL, CAST(DATEADD(MINUTE, (t.numero - 1) * 40 + 10, s.inicio) AS DATETIME2(0))), NEWID()
    FROM @t t INNER JOIN @s s ON s.id = t.idSesion;

    -- Marcas de la sesion 1: est1 AN/SJC/AN; est2 SJC/SJC/SJC; est3 AN/AN/AN; est4 sin cabecera; est5 (matricula no activa) SJC/SJC/SJC.
    -- Las sesiones 2, 3, 4 y 6 llevan SJC para est2 en todas sus tomas (asi solo las excluyen su estado, antiguedad, cancelacion o aviso previo)
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), e.idEG, s.id FROM #ataEst e CROSS JOIN @s s WHERE s.n IN (1, 2, 3, 4, 6) AND e.n <> 4;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(m.codigo = N'AN', 1, 0), rc.id, s.inicio, s.fin, t.idToma, 0, SYSUTCDATETIME()
    FROM dbo.Asistencia a
    INNER JOIN @s s ON s.id = a.sesion
    INNER JOIN #ataEst e ON e.idEG = a.estudianteGrupo
    INNER JOIN @t t ON t.idSesion = s.id
    CROSS APPLY (SELECT codigo = CASE WHEN s.n = 1 AND e.n = 1 THEN IIF(t.numero = 2, N'SJC', N'AN')
                                      WHEN s.n = 1 AND e.n = 3 THEN N'AN'
                                      WHEN s.n = 2 AND t.numero = 3 THEN NULL
                                      ELSE N'SJC' END) m
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = m.codigo
    WHERE s.n IN (1, 2, 3, 4, 6);
    INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, usuarioEjecutor, idCorrelacion) VALUES (@s4, @tipoCancelacion, N'ATA cancelada', @uD, NEWID());
    INSERT INTO dbo.AvisoFaltaSesion (sesion, fechaAvisoUtc, totalEstudiantesAvisados, idCorrelacion) VALUES (@s6, SYSUTCDATETIME(), 1, NEWID());

    -- --------------------------------------------------------------------------------------------------------
    -- C01: sesiones pendientes
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ataP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_falta @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ataP WHERE idSesion = @s1 AND idGrupo = @g AND fechaHoraFinUtc = (SELECT fin FROM @s WHERE n = 1))
       OR EXISTS (SELECT 1 FROM #ataP WHERE idGrupo = @g AND idSesion <> @s1)
        THROW 59110, 'TEST FAILED ATA_P1_C01_SESIONES_PENDIENTES: solo la sesion 1 (terminada, tomas cerradas, no cancelada, dentro del atraso, sin aviso) debe salir; no la de toma abierta, la de hace 30 h, la cancelada, la sin tomas, la avisada ni la en curso.', 1;
    TRUNCATE TABLE #ataP;
    INSERT INTO #ataP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_falta @idCorrelacion = @corr, @tamanoLote = 1;
    IF (SELECT COUNT(*) FROM #ataP) > 1
        THROW 59111, 'TEST FAILED ATA_P1_C01_SESIONES_PENDIENTES: @tamanoLote = 1 devuelve a lo sumo una sesion.', 1;
    TRUNCATE TABLE #ataP;
    PRINT 'TEST_PASS:ATA_P1_C01_SESIONES_PENDIENTES';

    -- --------------------------------------------------------------------------------------------------------
    -- C02: faltas por toma de la sesion 1
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ataF EXEC dbo.usp_consultar_faltas_sesion_aviso @idSesion = @s1, @idCorrelacion = @corr;
    DECLARE @u1 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ataEst WHERE n = 1), @u2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #ataEst WHERE n = 2);
    IF (SELECT COUNT(*) FROM #ataF) <> 4
       OR NOT EXISTS (SELECT 1 FROM #ataF WHERE idUsuarioEstudiante = @u1 AND numeroToma = 2 AND totalTomasSesion = 3 AND totalTomasEnFalta = 1
                      AND minutosFalta > 0 AND minutosFalta < 120
                      AND fechaPuntoControlUtc = DATEADD(MINUTE, 40, CAST((SELECT inicio FROM @s WHERE n = 1) AS DATETIME2(0))))
       OR (SELECT COUNT(*) FROM #ataF WHERE idUsuarioEstudiante = @u1) <> 1
       OR (SELECT COUNT(*) FROM #ataF WHERE idUsuarioEstudiante = @u2 AND totalTomasSesion = 3 AND totalTomasEnFalta = 3 AND minutosFalta = 120) <> 3
       OR EXISTS (SELECT 1 FROM #ataF WHERE idSesion <> @s1 OR idGrupo <> @g OR idAsignatura <> @idAsig OR correoEstudiante IS NULL OR nombreEstudiante IS NULL
                  OR nombreAsignatura IS NULL OR nombreGrupo IS NULL OR fechaLimiteReclamoUtc IS NULL
                  OR fechaLimiteReclamoUtc <> dbo.ufn_calcular_fecha_limite_justificacion(fechaHoraFinUtc))
       OR EXISTS (SELECT 1 FROM #ataF f INNER JOIN #ataEst e ON e.idUsuario = f.idUsuarioEstudiante WHERE e.n IN (3, 4, 5))
        THROW 59120, 'TEST FAILED ATA_P1_C02_FALTAS_POR_TOMA: est1 una fila (toma 2), est2 tres filas (falta general), sin est3 (AN), est4 (sin registro) ni est5 (matricula no activa).', 1;
    TRUNCATE TABLE #ataF;
    PRINT 'TEST_PASS:ATA_P1_C02_FALTAS_POR_TOMA';

    -- --------------------------------------------------------------------------------------------------------
    -- C03: registrar es idempotente y saca la sesion de las pendientes
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ataR EXEC dbo.usp_registrar_aviso_falta_sesion @idSesion = @s1, @totalEstudiantesAvisados = 2, @idCorrelacion = @corr;
    DECLARE @fechaAviso DATETIME2(3) = (SELECT fechaAvisoUtc FROM dbo.AvisoFaltaSesion WHERE sesion = @s1);
    IF NOT EXISTS (SELECT 1 FROM #ataR WHERE estado = 1 AND idCorrelacion = @corr) OR @fechaAviso IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion WHERE sesion = @s1 AND totalEstudiantesAvisados = 2 AND idCorrelacion = @corr)
        THROW 59130, 'TEST FAILED ATA_P1_C03_REGISTRAR_IDEMPOTENTE: la primera llamada escribe la marca con el total y la correlacion.', 1;
    TRUNCATE TABLE #ataR;
    INSERT INTO #ataR EXEC dbo.usp_registrar_aviso_falta_sesion @idSesion = @s1, @totalEstudiantesAvisados = 5, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ataR WHERE estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion WHERE sesion = @s1 AND totalEstudiantesAvisados = 2 AND fechaAvisoUtc = @fechaAviso)
       OR (SELECT COUNT(*) FROM dbo.AvisoFaltaSesion WHERE sesion = @s1) <> 1
        THROW 59131, 'TEST FAILED ATA_P1_C03_REGISTRAR_IDEMPOTENTE: la segunda llamada es exito sin escritura (el total y la fecha no cambian).', 1;
    TRUNCATE TABLE #ataR;
    INSERT INTO #ataP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_falta @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ataP WHERE idSesion = @s1)
        THROW 59132, 'TEST FAILED ATA_P1_C03_REGISTRAR_IDEMPOTENTE: una sesion avisada no vuelve a salir como pendiente.', 1;
    TRUNCATE TABLE #ataP;
    PRINT 'TEST_PASS:ATA_P1_C03_REGISTRAR_IDEMPOTENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- C04: sesion inexistente
    -- --------------------------------------------------------------------------------------------------------
    INSERT INTO #ataR EXEC dbo.usp_registrar_aviso_falta_sesion @idSesion = @corr, @totalEstudiantesAvisados = 1, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #ataR WHERE estado = 0 AND mt LIKE N'DBCODE=SES[_]001|%') OR EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion WHERE sesion = @corr)
        THROW 59140, 'TEST FAILED ATA_P1_C04_SESION_INEXISTENTE: una sesion inexistente responde SES_001 sin escribir.', 1;
    TRUNCATE TABLE #ataR;
    PRINT 'TEST_PASS:ATA_P1_C04_SESION_INEXISTENTE';

    -- --------------------------------------------------------------------------------------------------------
    -- C06 (antes de C05 para no repetir el reinicio): HORAS_MAXIMAS_ATRASO acota la antiguedad
    -- --------------------------------------------------------------------------------------------------------
    DELETE FROM dbo.AvisoFaltaSesion WHERE sesion = @s1;
    UPDATE dbo.CatalogoParametro SET valor = N'48' WHERE grupo = 'AVISO_FALTA_SESION' AND clave = 'HORAS_MAXIMAS_ATRASO';
    INSERT INTO #ataP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_falta @idCorrelacion = @corr, @tamanoLote = 100000;
    IF NOT EXISTS (SELECT 1 FROM #ataP WHERE idSesion = @s3) OR NOT EXISTS (SELECT 1 FROM #ataP WHERE idSesion = @s1)
        THROW 59160, 'TEST FAILED ATA_P1_C06_ATRASO_MAXIMO: con HORAS_MAXIMAS_ATRASO = 48 la sesion de hace 30 h tambien es pendiente.', 1;
    TRUNCATE TABLE #ataP;
    PRINT 'TEST_PASS:ATA_P1_C06_ATRASO_MAXIMO';

    -- --------------------------------------------------------------------------------------------------------
    -- C05: HABILITADO = false => 0 filas
    -- --------------------------------------------------------------------------------------------------------
    UPDATE dbo.CatalogoParametro SET valor = N'false' WHERE grupo = 'AVISO_FALTA_SESION' AND clave = 'HABILITADO';
    INSERT INTO #ataP EXEC dbo.usp_consultar_sesiones_pendientes_aviso_falta @idCorrelacion = @corr, @tamanoLote = 100000;
    IF EXISTS (SELECT 1 FROM #ataP)
        THROW 59150, 'TEST FAILED ATA_P1_C05_HABILITADO_FALSE: con HABILITADO = false no hay sesiones pendientes.', 1;
    TRUNCATE TABLE #ataP;
    PRINT 'TEST_PASS:ATA_P1_C05_HABILITADO_FALSE';

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
    THROW 59198, 'TEST FAILED ATA_P1_TRANCOUNT_ZERO: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:ATA_P1_C_TRANCOUNT_ZERO';
PRINT 'TEST END: test_ata_p1_aviso_falta';
GO
