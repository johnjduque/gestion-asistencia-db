USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1, migracion 54): faltas por reclamar del estudiante.
--   ATA_D10_00_OBJETOS_Y_PERMISOS   vista, SP y EXECUTE del rol runtime
--   ATA_D10_01_ANTES_DEL_AVISO      sin fila en AvisoFaltaSesion no hay faltas reclamables
--   ATA_D10_02_TOMAS_EN_FALTA       con el aviso, una fila por toma en SJC (est1: tomas 1 y 3), columnas; AN y matricula no activa no salen
--   ATA_D10_03_RECLAMO              reclamo radicado: sale la toma; reclamo retirado: vuelve
--   ATA_D10_04_PLAZO_VENCIDO        una sesion avisada con plazo vencido no sale
--   ATA_D10_05_MARCA_CORREGIDA      el docente corrige SJC a AN: la toma desaparece
--   ATA_D10_06_MATRICULA_CANCELADA  una matricula no activa no ve filas
--   ATA_D10_07_AISLAMIENTO          cada estudiante solo ve las suyas
--   ATA_D10_08_PAGINACION           orden fechaHoraFinUtc DESC, numeroToma ASC y totalRegistros
--   ATA_D10_09_RBAC_Y_VALIDACIONES  docente (SEC_001), usuario nulo (GEN_002), correlacion nula, PAG_001
--   ATA_D10_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida.
PRINT 'TEST START: test_ata_d10_faltas_reclamables';

IF OBJECT_ID(N'dbo.uv_falta_reclamable_estudiante', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_faltas_reclamables_estudiante', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                  WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_faltas_reclamables_estudiante', N'P') AND dp.permission_name = N'EXECUTE'
                    AND dp.state IN ('G', 'W') AND pr.name = N'rol_asistencias_runtime')
    THROW 59500, 'TEST FAILED ATA_D10_00_OBJETOS_Y_PERMISOS: faltan la vista, el SP o el EXECUTE del rol runtime (migracion 54).', 1;
PRINT 'TEST_PASS:ATA_D10_00_OBJETOS_Y_PERMISOS';
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a WHERE a.estaActivaAsignatura = 1 ORDER BY a.id);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoNoA UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo <> 'A' ORDER BY codigo);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @pending UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
DECLARE @retirado UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5)));
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
IF @tipoCC IS NULL OR @idAsig IS NULL OR @idInstitucion IS NULL OR @estadoA IS NULL OR @estadoNoA IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL
   OR @pending IS NULL OR @retirado IS NULL
    THROW 59501, 'TEST FAILED ATA_D10: faltan fixtures del seed (asignatura, institucion, estados de matricula, de toma y de reclamo).', 1;

CREATE TABLE #d10R (idEstudianteGrupo UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(200), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200),
    idSesion UNIQUEIDENTIFIER, numeroSesion INT, fechaHoraInicioUtc DATETIME2(7), fechaHoraFinUtc DATETIME2(7), idToma UNIQUEIDENTIFIER, numeroToma SMALLINT,
    fechaPuntoControlUtc DATETIME2(7), fechaLimiteReclamoUtc DATETIME2(7), totalRegistros INT);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    CREATE TABLE #d10E (n INT, idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER);
    INSERT INTO #d10E (n, idUsuario, idEstudiante, idEG) SELECT v.n, NEWID(), NEWID(), NEWID() FROM (VALUES (1),(2),(3),(4)) v(n);
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 979000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Titular', N'D10', N'Doc', N'D10', CONCAT(N'ata.d10.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_ATA');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT e.idUsuario, @tipoCC, 980000000 + e.n * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Reclamable', e.n), N'Falta', N'Est', N'D10',
           CONCAT(N'ata.d10.e', e.n, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_ATA'
    FROM #d10E e;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #d10E;
    DECLARE @per UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInstitucion, N'ATA periodo d10', 3980000 + ABS(CHECKSUM(NEWID()) % 20000), DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 959000 + ABS(CHECKSUM(NEWID()) % 4999), N'ATA Grupo d10', 30, 0, 0, 0, @d);
    -- est1, est2 y est4 con matricula activa; est3 con matricula no activa
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT e.idEG, IIF(e.n = 3, @estadoNoA, @estadoA), e.idEstudiante, @g FROM #d10E e;

    -- Sesiones: S1 terminada hace 30 min con 3 tomas (est1 SJC/AN/SJC, est2 SJC x3, est3 SJC x3); S2 avisada con plazo vencido (hace 12 dias, 1 toma, est1 SJC);
    -- S4 terminada hace 24 h con 1 toma (est2 SJC), avisada. est4 sin cabecera de asistencia.
    DECLARE @s TABLE (n INT PRIMARY KEY, id UNIQUEIDENTIFIER, inicio DATETIME2(7), fin DATETIME2(7), tomas INT);
    INSERT INTO @s (n, id, inicio, fin, tomas) VALUES
        (1, NEWID(), DATEADD(MINUTE, -150, SYSUTCDATETIME()), DATEADD(MINUTE, -30, SYSUTCDATETIME()), 3),
        (2, NEWID(), DATEADD(MINUTE, -(12 * 1440 + 120), SYSUTCDATETIME()), DATEADD(MINUTE, -(12 * 1440), SYSUTCDATETIME()), 1),
        (4, NEWID(), DATEADD(MINUTE, -(1440 + 120), SYSUTCDATETIME()), DATEADD(MINUTE, -1440, SYSUTCDATETIME()), 1);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT s.id, CONCAT(N'ATA d10 S', s.n), s.n, CONCAT(N'D10', s.n, N'x', @tag), 1, @g, s.inicio, s.fin, N'UTC_V2' FROM @s s;
    DECLARE @s1 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 1), @s2 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 2), @s4 UNIQUEIDENTIFIER = (SELECT id FROM @s WHERE n = 4);
    DECLARE @t TABLE (idSesion UNIQUEIDENTIFIER, numero SMALLINT, idToma UNIQUEIDENTIFIER, PRIMARY KEY (idSesion, numero));
    INSERT INTO @t (idSesion, numero, idToma) SELECT s.id, v.numero, NEWID() FROM @s s INNER JOIN (VALUES (1), (2), (3)) v(numero) ON v.numero <= s.tomas;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT t.idToma, t.idSesion, t.numero, @modoManual, @estCerrada, 0, @d,
           CAST(DATEADD(MINUTE, (t.numero - 1) * 40, s.inicio) AS DATETIME2(0)), CAST(DATEADD(MINUTE, (t.numero - 1) * 40 + 10, s.inicio) AS DATETIME2(0)), NEWID()
    FROM @t t INNER JOIN @s s ON s.id = t.idSesion;
    -- cabeceras: S1 para est1..3, S2 para est1, S4 para est2
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), e.idEG, s.id FROM #d10E e INNER JOIN @s s ON (s.n = 1 AND e.n IN (1, 2, 3)) OR (s.n = 2 AND e.n = 1) OR (s.n = 4 AND e.n = 2);
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, IIF(m.codigo = N'AN', 1, 0), rc.id, s.inicio, s.fin, t.idToma, 0, SYSUTCDATETIME()
    FROM dbo.Asistencia a
    INNER JOIN @s s ON s.id = a.sesion
    INNER JOIN #d10E e ON e.idEG = a.estudianteGrupo
    INNER JOIN @t t ON t.idSesion = s.id
    CROSS APPLY (SELECT codigo = IIF(s.n = 1 AND e.n = 1 AND t.numero = 2, N'AN', N'SJC')) m
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = m.codigo;
    DECLARE @u1 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #d10E WHERE n = 1), @u2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #d10E WHERE n = 2);
    DECLARE @u3 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #d10E WHERE n = 3), @u4 UNIQUEIDENTIFIER = (SELECT idUsuario FROM #d10E WHERE n = 4);
    DECLARE @eg1 UNIQUEIDENTIFIER = (SELECT idEG FROM #d10E WHERE n = 1), @eg2 UNIQUEIDENTIFIER = (SELECT idEG FROM #d10E WHERE n = 2);

    -- D10_01: ninguna sesion tiene aviso todavia
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #d10R)
        THROW 59510, 'TEST FAILED ATA_D10_01_ANTES_DEL_AVISO: sin fila en AvisoFaltaSesion no hay faltas reclamables.', 1;
    TRUNCATE TABLE #d10R;
    PRINT 'TEST_PASS:ATA_D10_01_ANTES_DEL_AVISO';

    -- D10_02: con el aviso de S1, S2 y S4
    INSERT INTO dbo.AvisoFaltaSesion (sesion, fechaAvisoUtc, totalEstudiantesAvisados, idCorrelacion)
    SELECT id, SYSUTCDATETIME(), 1, NEWID() FROM @s;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #d10R) <> 2
       OR (SELECT COUNT(*) FROM #d10R WHERE numeroToma IN (1, 3) AND idSesion = @s1 AND idEstudianteGrupo = @eg1 AND idGrupo = @g AND idAsignatura = @idAsig AND numeroSesion = 1
              AND nombreGrupo = N'ATA Grupo d10' AND nombreAsignatura IS NOT NULL AND totalRegistros = 2 AND idToma IS NOT NULL
              AND fechaHoraInicioUtc = (SELECT inicio FROM @s WHERE n = 1) AND fechaHoraFinUtc = (SELECT fin FROM @s WHERE n = 1)
              AND fechaPuntoControlUtc IS NOT NULL
              AND fechaLimiteReclamoUtc = dbo.ufn_calcular_fecha_limite_justificacion(fechaHoraFinUtc)) <> 2
        THROW 59520, 'TEST FAILED ATA_D10_02_TOMAS_EN_FALTA: est1 (SJC en las tomas 1 y 3, AN en la 2) ve exactamente las tomas 1 y 3 de S1 con todas las columnas; la toma AN y la sesion de plazo vencido no salen.', 1;
    TRUNCATE TABLE #d10R;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u3, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #d10R)
        THROW 59521, 'TEST FAILED ATA_D10_02_TOMAS_EN_FALTA: la matricula no activa (est3) no ve filas.', 1;
    TRUNCATE TABLE #d10R;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u4, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #d10R)
        THROW 59522, 'TEST FAILED ATA_D10_02_TOMAS_EN_FALTA: un estudiante sin marcas (est4) no ve filas.', 1;
    TRUNCATE TABLE #d10R;
    PRINT 'TEST_PASS:ATA_D10_02_TOMAS_EN_FALTA';

    -- D10_03: reclamo radicado de la toma 1 => solo la toma 3; retirado => vuelve
    DECLARE @sol UNIQUEIDENTIFIER = NEWID();
    DECLARE @a1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Asistencia WHERE estudianteGrupo = @eg1 AND sesion = @s1);
    DECLARE @toma1 UNIQUEIDENTIFIER = (SELECT idToma FROM @t WHERE idSesion = @s1 AND numero = 1);
    INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta, toma)
    VALUES (@sol, N'REC-D10', @a1, CAST(SYSUTCDATETIME() AS DATE), @pending, N'Cita medica D10', N'', @toma1);
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #d10R) <> 1 OR NOT EXISTS (SELECT 1 FROM #d10R WHERE numeroToma = 3 AND totalRegistros = 1)
        THROW 59530, 'TEST FAILED ATA_D10_03_RECLAMO: con el reclamo de la toma 1 radicado solo queda la toma 3.', 1;
    TRUNCATE TABLE #d10R;
    UPDATE dbo.SolicitudRevisionAsistencia SET estado = @retirado WHERE id = @sol;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #d10R) <> 2 OR NOT EXISTS (SELECT 1 FROM #d10R WHERE numeroToma = 1)
        THROW 59531, 'TEST FAILED ATA_D10_03_RECLAMO: con el reclamo retirado la toma 1 vuelve a ser reclamable.', 1;
    TRUNCATE TABLE #d10R;
    PRINT 'TEST_PASS:ATA_D10_03_RECLAMO';

    -- D10_04: plazo vencido. S2 (hace 12 dias, avisada) no sale; la misma sesion dentro del plazo si (control)
    IF EXISTS (SELECT 1 FROM dbo.uv_falta_reclamable_estudiante WHERE idSesion = @s2)
        THROW 59540, 'TEST FAILED ATA_D10_04_PLAZO_VENCIDO: una sesion avisada con plazo vencido no genera faltas reclamables.', 1;
    UPDATE dbo.Sesion SET procedenciaTemporal = N'UTC_V2', fechaHoraInicio = DATEADD(HOUR, -2, SYSUTCDATETIME()), fechaHoraFin = DATEADD(MINUTE, -30, SYSUTCDATETIME()) WHERE id = @s2;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_falta_reclamable_estudiante WHERE idSesion = @s2 AND idEstudianteGrupo = @eg1)
        THROW 59541, 'TEST FAILED ATA_D10_04_PLAZO_VENCIDO: la misma sesion dentro del plazo si es reclamable (control).', 1;
    UPDATE dbo.Sesion SET procedenciaTemporal = N'UTC_V2', fechaHoraInicio = DATEADD(MINUTE, -(12 * 1440 + 120), SYSUTCDATETIME()), fechaHoraFin = DATEADD(MINUTE, -(12 * 1440), SYSUTCDATETIME()) WHERE id = @s2;
    PRINT 'TEST_PASS:ATA_D10_04_PLAZO_VENCIDO';

    -- D10_05: el docente corrige la marca de la toma 3 de est1 a AN => desaparece
    DECLARE @toma3 UNIQUEIDENTIFIER = (SELECT idToma FROM @t WHERE idSesion = @s1 AND numero = 3);
    UPDATE da SET razonCausa = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'AN'), asistio = 1
    FROM dbo.DetalleAsistencia da WHERE da.asistencia = @a1 AND da.toma = @toma3;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #d10R) <> 1 OR EXISTS (SELECT 1 FROM #d10R WHERE numeroToma = 3)
        THROW 59550, 'TEST FAILED ATA_D10_05_MARCA_CORREGIDA: la toma corregida a AN desaparece de la lista.', 1;
    TRUNCATE TABLE #d10R;
    PRINT 'TEST_PASS:ATA_D10_05_MARCA_CORREGIDA';

    -- D10_06: matricula cancelada de est2 => 0 filas
    UPDATE dbo.EstudianteGrupo SET estado = @estadoNoA WHERE id = @eg2;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u2, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #d10R)
        THROW 59560, 'TEST FAILED ATA_D10_06_MATRICULA_CANCELADA: una matricula no activa no ve faltas reclamables.', 1;
    TRUNCATE TABLE #d10R;
    UPDATE dbo.EstudianteGrupo SET estado = @estadoA WHERE id = @eg2;
    PRINT 'TEST_PASS:ATA_D10_06_MATRICULA_CANCELADA';

    -- D10_07: aislamiento. est2 solo ve sus tomas; est1 no ve las de est2
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u2, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #d10R) <> 4 OR EXISTS (SELECT 1 FROM #d10R WHERE idEstudianteGrupo <> @eg2)
        THROW 59570, 'TEST FAILED ATA_D10_07_AISLAMIENTO: est2 ve solo sus 4 tomas (S1 x3 y S4 x1).', 1;
    TRUNCATE TABLE #d10R;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr;
    IF EXISTS (SELECT 1 FROM #d10R WHERE idEstudianteGrupo <> @eg1)
        THROW 59571, 'TEST FAILED ATA_D10_07_AISLAMIENTO: est1 no ve filas de otro estudiante.', 1;
    TRUNCATE TABLE #d10R;
    PRINT 'TEST_PASS:ATA_D10_07_AISLAMIENTO';

    -- D10_08: paginacion y orden (S1 termina despues que S4): S1 t1, t2, t3, S4 t1
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u2, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 3;
    IF (SELECT COUNT(*) FROM #d10R) <> 3 OR EXISTS (SELECT 1 FROM #d10R WHERE totalRegistros <> 4 OR idSesion <> @s1)
        THROW 59580, 'TEST FAILED ATA_D10_08_PAGINACION: la pagina 1 (tamano 3) trae las 3 tomas de la sesion mas reciente y totalRegistros = 4.', 1;
    TRUNCATE TABLE #d10R;
    INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u2, @idCorrelacion = @corr, @numeroPagina = 2, @tamanoPagina = 3;
    IF (SELECT COUNT(*) FROM #d10R) <> 1 OR NOT EXISTS (SELECT 1 FROM #d10R WHERE idSesion = @s4 AND numeroToma = 1 AND totalRegistros = 4)
        THROW 59582, 'TEST FAILED ATA_D10_08_PAGINACION: la pagina 2 trae la toma de la sesion anterior (S4) con totalRegistros = 4.', 1;
    TRUNCATE TABLE #d10R;
    -- tamano 1: cada pagina trae la fila siguiente del orden fechaHoraFinUtc DESC, numeroToma ASC
    DECLARE @orden NVARCHAR(100) = N'', @pg INT = 1, @tag1 NVARCHAR(10);
    WHILE @pg <= 4
    BEGIN
        INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u2, @idCorrelacion = @corr, @numeroPagina = @pg, @tamanoPagina = 1;
        SELECT @tag1 = CONCAT(IIF(idSesion = @s1, N'S1', N'S4'), N'T', numeroToma) FROM #d10R;
        SET @orden = @orden + IIF(@orden = N'', N'', N',') + @tag1;
        TRUNCATE TABLE #d10R;
        SET @pg += 1;
    END
    IF @orden <> N'S1T1,S1T2,S1T3,S4T1'
        THROW 59584, 'TEST FAILED ATA_D10_08_PAGINACION: el orden es fechaHoraFinUtc DESC, numeroToma ASC (S1 t1-t3 y luego S4 t1).', 1;
    PRINT 'TEST_PASS:ATA_D10_08_PAGINACION';

    -- D10_09: RBAC y validaciones (THROW 51000 con el codigo en el mensaje tecnico)
    DECLARE @err NVARCHAR(4000), @num INT;
    BEGIN TRY INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @uD, @idCorrelacion = @corr;
    END TRY BEGIN CATCH SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER(); END CATCH;
    IF @num <> 51000 OR @err NOT LIKE N'%DBCODE=SEC[_]001|%'
        THROW 59590, 'TEST FAILED ATA_D10_09_RBAC_Y_VALIDACIONES: un docente no consulta faltas reclamables de estudiante (SEC_001, THROW 51000).', 1;
    SELECT @err = NULL, @num = NULL;
    BEGIN TRY INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @corr;
    END TRY BEGIN CATCH SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER(); END CATCH;
    IF @num <> 51000 OR @err NOT LIKE N'%DBCODE=GEN[_]002|%'
        THROW 59591, 'TEST FAILED ATA_D10_09_RBAC_Y_VALIDACIONES: idUsuarioEjecutor nulo responde GEN_002 (THROW 51000).', 1;
    SELECT @err = NULL, @num = NULL;
    BEGIN TRY INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = NULL;
    END TRY BEGIN CATCH SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER(); END CATCH;
    IF @num <> 51000
        THROW 59592, 'TEST FAILED ATA_D10_09_RBAC_Y_VALIDACIONES: la correlacion nula se rechaza con THROW 51000.', 1;
    SELECT @err = NULL, @num = NULL;
    BEGIN TRY INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr, @numeroPagina = 0, @tamanoPagina = 20;
    END TRY BEGIN CATCH SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER(); END CATCH;
    IF @num <> 51000 OR @err NOT LIKE N'%DBCODE=PAG[_]001|%'
        THROW 59593, 'TEST FAILED ATA_D10_09_RBAC_Y_VALIDACIONES: numeroPagina 0 responde PAG_001.', 1;
    SELECT @err = NULL, @num = NULL;
    BEGIN TRY INSERT INTO #d10R EXEC dbo.usp_consultar_faltas_reclamables_estudiante @idUsuarioEjecutor = @u1, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100000;
    END TRY BEGIN CATCH SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER(); END CATCH;
    IF @num <> 51000 OR @err NOT LIKE N'%DBCODE=PAG[_]001|%'
        THROW 59594, 'TEST FAILED ATA_D10_09_RBAC_Y_VALIDACIONES: un tamano de pagina sobre el maximo responde PAG_001.', 1;
    PRINT 'TEST_PASS:ATA_D10_09_RBAC_Y_VALIDACIONES';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59597, @msg, 1;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 59598, 'TEST FAILED ATA_D10_TRANCOUNT_ZERO: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:ATA_D10_TRANCOUNT_ZERO';
PRINT 'TEST END: test_ata_d10_faltas_reclamables';
GO
