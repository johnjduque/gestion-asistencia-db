USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- CIERRE-W1A (docs/work-items/CIERRE-W1A-docente-reclamos-padron): filtros y paginacion en el servidor para el docente.
--   usp_consultar_solicitudes_revision_docente      + @busqueda, @idGrupo   (resultset sin cambios, 31 columnas)
--   usp_consultar_estudiantes_grupo_ambito_paginado + @busqueda             (resultset sin cambios, 8 columnas)
--   W1A_REC_01_BUSQUEDA_JUSTIFICACION  la busqueda por texto de la justificacion acota filas y total, sin distinguir mayusculas
--   W1A_REC_02_BUSQUEDA_CAMPOS         estudiante, codigo y nombre de asignatura; vacio = sin filtro; sin coincidencias = 0 filas
--   W1A_REC_03_FILTRO_GRUPO            @idGrupo acota; un grupo ajeno (en cualquier sentido) o inexistente da 0 filas
--   W1A_REC_04_PAGINACION_TOTAL        con filtro, las paginas parten el resultado y totalRegistros es el total filtrado
--   W1A_REC_05_SIN_FILTROS_IGUAL       sin los parametros nuevos el resultado es el de siempre (compatibilidad con el backend viejo)
--   W1A_PAD_01_BUSQUEDA                padron: nombre y documento; sin coincidencias = 0 filas
--   W1A_PAD_02_PAGINACION_TOTAL        las paginas del padron suman el total filtrado
--   W1A_PAD_03_SIN_BUSQUEDA_IGUAL      sin @busqueda (NULL o espacios) y con @tamanoPagina NULL el padron sigue completo
--   W1A_PAD_04_AMBITO                  otro docente o un grupo inexistente: SEC_002 tambien con @busqueda
--   W1A_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida (salvo W1A_PAD_04, que solo lee).
PRINT 'TEST START: test_cierre_w1a_docente_reclamos_padron (CIERRE-W1A)';
GO

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @teacher2 UNIQUEIDENTIFIER, @group2 UNIQUEIDENTIFIER;
DECLARE @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER, @estadoP UNIQUEIDENTIFIER, @estA UNIQUEIDENTIFIER, @tipoCC UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente FROM dbo.Grupo g WHERE g.docente IS NOT NULL ORDER BY g.id;
SELECT TOP 1 @group2 = g.id, @teacher2 = g.docente FROM dbo.Grupo g WHERE g.docente IS NOT NULL AND g.docente <> @teacher ORDER BY g.id;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT @userT2 = usuario FROM dbo.Docente WHERE id = @teacher2;
SELECT @estadoP = id FROM dbo.Estado WHERE codigo = 'P';
SELECT @estA = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A';
SELECT TOP 1 @tipoCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
IF @group IS NULL OR @group2 IS NULL OR @userT IS NULL OR @userT2 IS NULL OR @estadoP IS NULL OR @estA IS NULL OR @tipoCC IS NULL
    THROW 58400, 'TEST FAILED W1A: faltan fixtures del seed (dos grupos de dos docentes distintos, estado P, estado A, tipo CC).', 1;

DECLARE @uA UNIQUEIDENTIFIER = NEWID(), @uB UNIQUEIDENTIFIER = NEWID(), @uC UNIQUEIDENTIFIER = NEWID();
DECLARE @eA UNIQUEIDENTIFIER = NEWID(), @eB UNIQUEIDENTIFIER = NEWID(), @eC UNIQUEIDENTIFIER = NEWID();
DECLARE @egA UNIQUEIDENTIFIER = NEWID(), @egB UNIQUEIDENTIFIER = NEWID(), @egC UNIQUEIDENTIFIER = NEWID();
DECLARE @session UNIQUEIDENTIFIER = NEWID(), @asisA UNIQUEIDENTIFIER = NEWID(), @asisB UNIQUEIDENTIFIER = NEWID();
DECLARE @reqA UNIQUEIDENTIFIER = NEWID(), @reqB UNIQUEIDENTIFIER = NEWID();
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @inicio DATETIME2(7) = '2026-10-19T15:30:00';
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @rows INT, @total INT, @codigoAsig NVARCHAR(100), @nombreAsig NVARCHAR(100);
DECLARE @docA NVARCHAR(20) = N'1979000001';

SELECT @codigoAsig = a.codigo, @nombreAsig = a.nombre FROM dbo.Grupo g INNER JOIN dbo.Asignatura a ON a.id = g.asignatura WHERE g.id = @group;

CREATE TABLE #w1aR (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT,
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), totalSoportes INT,
    idToma UNIQUEIDENTIFIER, numeroToma SMALLINT, fechaPuntoControlUtc DATETIME2(7));
CREATE TABLE #w1aE (id UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, documento NVARCHAR(20), nombreCompleto NVARCHAR(400),
    correo NVARCHAR(100), codigoEstado NVARCHAR(10), nombreEstado NVARCHAR(100), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Tres estudiantes nuevos del grupo, con nombres y documentos propios (no chocan con el seed)
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uA, @tipoCC, 1979000001, N'Padronw1a', N'Qa', N'Alfaw1a', N'X', N'w1a.alfa@test.local', 1, 1),
           (@uB, @tipoCC, 1979000002, N'Padronw1a', N'Qa', N'Betaw1a', N'X', N'w1a.beta@test.local', 1, 1),
           (@uC, @tipoCC, 1979000003, N'Padronw1a', N'Qa', N'Gammaw1a', N'X', N'w1a.gamma@test.local', 1, 1);
    INSERT dbo.Estudiante (id, usuario) VALUES (@eA, @uA), (@eB, @uB), (@eC, @uC);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@egA, @estA, @eA, @group), (@egB, @estA, @eB, @group), (@egC, @estA, @eC, @group);

    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA W1A', @number, @sessionCode, 1, @group, @inicio, DATEADD(HOUR, 1, @inicio));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asisA, @egA, @session), (@asisB, @egB, @session);
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reqA, N'QA-W1A-A', @asisA, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'W1A_TOKEN motivo cita medica alfa', ''),
           (@reqB, N'QA-W1A-B', @asisB, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'W1A_TOKEN motivo calamidad beta', '');

    -- ===== W1A_REC_01: busqueda por texto de la justificacion (sin distinguir mayusculas)
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'CALAMIDAD';
    SELECT @rows = COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB);
    SET @ok = IIF(@rows = 1 AND EXISTS (SELECT 1 FROM #w1aR WHERE idSolicitudRevisionAsistencia = @reqB), 1, 0);
    IF @ok <> 1 THROW 58401, 'TEST FAILED: W1A_REC_01_BUSQUEDA_JUSTIFICACION (filtro)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'  w1a_token  ';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2
                  AND NOT EXISTS (SELECT 1 FROM #w1aR WHERE totalRegistros <> (SELECT COUNT(*) FROM #w1aR)), 1, 0);
    IF @ok <> 1 THROW 58402, 'TEST FAILED: W1A_REC_01_BUSQUEDA_JUSTIFICACION (mayusculas, recorte y total)', 1;
    PRINT 'TEST_PASS:W1A_REC_01_BUSQUEDA_JUSTIFICACION';

    -- ===== W1A_REC_02: estudiante, codigo y nombre de la asignatura; vacio = sin filtro; sin coincidencias = 0 filas
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'Alfaw1a';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR) = 1 AND EXISTS (SELECT 1 FROM #w1aR WHERE idSolicitudRevisionAsistencia = @reqA), 1, 0);
    IF @ok <> 1 THROW 58403, 'TEST FAILED: W1A_REC_02_BUSQUEDA_CAMPOS (estudiante)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @codigoAsig;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2, 1, 0);
    IF @ok <> 1 THROW 58404, 'TEST FAILED: W1A_REC_02_BUSQUEDA_CAMPOS (codigo de la asignatura)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @nombreAsig;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2, 1, 0);
    IF @ok <> 1 THROW 58405, 'TEST FAILED: W1A_REC_02_BUSQUEDA_CAMPOS (nombre de la asignatura)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'   ';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2, 1, 0);
    IF @ok <> 1 THROW 58406, 'TEST FAILED: W1A_REC_02_BUSQUEDA_CAMPOS (vacio = sin filtro)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'zzz_sin_coincidencias_w1a';
    IF (SELECT COUNT(*) FROM #w1aR) <> 0 THROW 58407, 'TEST FAILED: W1A_REC_02_BUSQUEDA_CAMPOS (sin coincidencias)', 1;
    PRINT 'TEST_PASS:W1A_REC_02_BUSQUEDA_CAMPOS';

    -- ===== W1A_REC_03: filtro por grupo; el ambito (titularidad) se mantiene dentro del SP
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @group;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2
                  AND NOT EXISTS (SELECT 1 FROM #w1aR WHERE idGrupo <> @group), 1, 0);
    IF @ok <> 1 THROW 58408, 'TEST FAILED: W1A_REC_03_FILTRO_GRUPO (propio)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @group2;
    IF (SELECT COUNT(*) FROM #w1aR) <> 0 THROW 58409, 'TEST FAILED: W1A_REC_03_FILTRO_GRUPO (grupo de otro docente)', 1;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @group;
    IF (SELECT COUNT(*) FROM #w1aR) <> 0 THROW 58410, 'TEST FAILED: W1A_REC_03_FILTRO_GRUPO (otro docente pide el grupo ajeno)', 1;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @reqA;  -- GUID que no es de ningun grupo
    IF (SELECT COUNT(*) FROM #w1aR) <> 0 THROW 58411, 'TEST FAILED: W1A_REC_03_FILTRO_GRUPO (grupo inexistente)', 1;
    PRINT 'TEST_PASS:W1A_REC_03_FILTRO_GRUPO';

    -- ===== W1A_REC_04: paginas con filtro; totalRegistros es el total filtrado, no el de la pagina
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 1, @busqueda = N'W1A_TOKEN', @idGrupo = @group;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 2, @tamanoPagina = 1, @busqueda = N'W1A_TOKEN', @idGrupo = @group;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR) = 2 AND (SELECT COUNT(DISTINCT idSolicitudRevisionAsistencia) FROM #w1aR) = 2
                  AND NOT EXISTS (SELECT 1 FROM #w1aR WHERE totalRegistros <> 2), 1, 0);
    IF @ok <> 1 THROW 58412, 'TEST FAILED: W1A_REC_04_PAGINACION_TOTAL (paginas 1 y 2)', 1;
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 3, @tamanoPagina = 1, @busqueda = N'W1A_TOKEN', @idGrupo = @group;
    IF (SELECT COUNT(*) FROM #w1aR) <> 0 THROW 58413, 'TEST FAILED: W1A_REC_04_PAGINACION_TOTAL (pagina posterior a la ultima)', 1;
    PRINT 'TEST_PASS:W1A_REC_04_PAGINACION_TOTAL';

    -- ===== W1A_REC_05: sin los parametros nuevos el resultado es el de siempre (31 columnas, ambos reclamos, total coherente)
    DELETE FROM #w1aR;
    INSERT INTO #w1aR EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aR WHERE idSolicitudRevisionAsistencia IN (@reqA, @reqB)) = 2
                  AND NOT EXISTS (SELECT 1 FROM #w1aR WHERE totalRegistros <> (SELECT COUNT(*) FROM #w1aR))
                  AND (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), NULL)) = 31, 1, 0);
    IF @ok <> 1 THROW 58414, 'TEST FAILED: W1A_REC_05_SIN_FILTROS_IGUAL', 1;
    PRINT 'TEST_PASS:W1A_REC_05_SIN_FILTROS_IGUAL';

    -- ===== W1A_PAD_01: padron, busqueda por nombre y por documento
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'betaw1a';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aE) = 1 AND EXISTS (SELECT 1 FROM #w1aE WHERE idEstudiante = @eB AND totalRegistros = 1), 1, 0);
    IF @ok <> 1 THROW 58415, 'TEST FAILED: W1A_PAD_01_BUSQUEDA (nombre)', 1;
    DELETE FROM #w1aE;
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @docA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aE) = 1 AND EXISTS (SELECT 1 FROM #w1aE WHERE idEstudiante = @eA AND documento = @docA), 1, 0);
    IF @ok <> 1 THROW 58416, 'TEST FAILED: W1A_PAD_01_BUSQUEDA (documento)', 1;
    DELETE FROM #w1aE;
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'padronw1a';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aE) = 3 AND NOT EXISTS (SELECT 1 FROM #w1aE WHERE totalRegistros <> 3), 1, 0);
    IF @ok <> 1 THROW 58417, 'TEST FAILED: W1A_PAD_01_BUSQUEDA (apellido comun)', 1;
    DELETE FROM #w1aE;
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 100, @busqueda = N'zzz_sin_coincidencias_w1a';
    IF (SELECT COUNT(*) FROM #w1aE) <> 0 THROW 58418, 'TEST FAILED: W1A_PAD_01_BUSQUEDA (sin coincidencias)', 1;
    PRINT 'TEST_PASS:W1A_PAD_01_BUSQUEDA';

    -- ===== W1A_PAD_02: las paginas suman el total filtrado
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 2, @busqueda = N'padronw1a';
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @numeroPagina = 2, @tamanoPagina = 2, @busqueda = N'padronw1a';
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aE) = 3 AND (SELECT COUNT(DISTINCT id) FROM #w1aE) = 3
                  AND NOT EXISTS (SELECT 1 FROM #w1aE WHERE totalRegistros <> 3), 1, 0);
    IF @ok <> 1 THROW 58419, 'TEST FAILED: W1A_PAD_02_PAGINACION_TOTAL', 1;
    PRINT 'TEST_PASS:W1A_PAD_02_PAGINACION_TOTAL';

    -- ===== W1A_PAD_03: sin busqueda (NULL o espacios) y con @tamanoPagina NULL el padron sigue completo
    DELETE FROM #w1aE;
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SELECT @total = (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group);
    SET @ok = IIF((SELECT COUNT(*) FROM #w1aE) = @total AND @total >= 3 AND NOT EXISTS (SELECT 1 FROM #w1aE WHERE totalRegistros <> @total), 1, 0);
    IF @ok <> 1 THROW 58420, 'TEST FAILED: W1A_PAD_03_SIN_BUSQUEDA_IGUAL (completo)', 1;
    DELETE FROM #w1aE;
    INSERT INTO #w1aE EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @busqueda = N'   ';
    IF (SELECT COUNT(*) FROM #w1aE) <> @total THROW 58421, 'TEST FAILED: W1A_PAD_03_SIN_BUSQUEDA_IGUAL (espacios = sin filtro)', 1;
    PRINT 'TEST_PASS:W1A_PAD_03_SIN_BUSQUEDA_IGUAL';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #w1aR;
    DROP TABLE IF EXISTS #w1aE;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #w1aR;
DROP TABLE IF EXISTS #w1aE;
GO

-- ===== W1A_PAD_04: el ambito se valida dentro del SP, tambien con @busqueda (solo lectura: sin transaccion)
DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @msg NVARCHAR(4000), @rechazos INT = 0;
SELECT TOP 1 @group = g.id, @teacher = g.docente FROM dbo.Grupo g WHERE g.docente IS NOT NULL ORDER BY g.id;
SELECT TOP 1 @userT2 = d.usuario FROM dbo.Docente d WHERE d.id <> @teacher ORDER BY d.id;
IF @group IS NULL OR @userT2 IS NULL THROW 58422, 'TEST FAILED W1A_PAD_04: faltan fixtures del seed.', 1;
CREATE TABLE #w1aE2 (id UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, documento NVARCHAR(20), nombreCompleto NVARCHAR(400),
    correo NVARCHAR(100), codigoEstado NVARCHAR(10), nombreEstado NVARCHAR(100), totalRegistros INT);
BEGIN TRY
    INSERT INTO #w1aE2 EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @group, @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 10, @busqueda = N'a';
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
    IF CHARINDEX(N'SEC_002', @msg) > 0 SET @rechazos += 1;
END CATCH;
BEGIN TRY
    INSERT INTO #w1aE2 EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @corr, @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 10, @busqueda = N'a';
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
    IF CHARINDEX(N'SEC_002', @msg) > 0 SET @rechazos += 1;
END CATCH;
DROP TABLE IF EXISTS #w1aE2;
IF @rechazos <> 2 THROW 58423, 'TEST FAILED: W1A_PAD_04_AMBITO (otro docente y grupo inexistente deben dar SEC_002)', 1;
PRINT 'TEST_PASS:W1A_PAD_04_AMBITO';
GO

IF @@TRANCOUNT <> 0
    THROW 58424, 'TEST FAILED: W1A_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:W1A_TRANCOUNT_ZERO';
PRINT 'TEST PASS: test_cierre_w1a_docente_reclamos_padron';
GO
