USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CIERRE-W2B (decision de producto 2026-11-16): sesiones y resumen del estudiante resueltos en la base.
--   W2B_SES_01..05  usp_consultar_sesiones_materia_estudiante: orden cronologico determinista (inicio, numero, id), paginas sin
--                   repetir ni saltar filas, total real, filtro opcional @idGrupo y aislamiento por estudiante
--   W2B_RES_01..06  usp_consultar_resumen_materias_estudiante: coherencia con usp_consultar_materias_estudiante (mismas materias),
--                   horas de falta y materias en riesgo con la regla y los umbrales de la base, solo matricula inscrita,
--                   aislamiento, rechazos y permiso del runtime
-- Corre en UNA transaccion con ROLLBACK final. Los THROW esperados (XACT_ABORT ON dentro del SP) se capturan DESPUES del rollback.
-- Fixture: dos estudiantes inscritos en grupos distintos de la misma asignatura (semilla LB-004D); el estudiante A se inscribe
-- ademas en el grupo del estudiante B para tener dos materias (asignatura y grupo) con sesiones desordenadas por numero.
-- ============================================================================
IF OBJECT_ID('tempdb..#w2b_expect') IS NOT NULL DROP PROCEDURE #w2b_expect;
GO
CREATE PROCEDURE #w2b_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: W2B_', @label);
        THROW 56301, @mensaje, 1;
    END
END;
GO

PRINT 'TEST START: test_w2b_estudiante_resumen';
DECLARE @inscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @asig UNIQUEIDENTIFIER, @g1 UNIQUEIDENTIFIER, @g2 UNIQUEIDENTIFIER, @eA UNIQUEIDENTIFIER, @eB UNIQUEIDENTIFIER;
DECLARE @uA UNIQUEIDENTIFIER, @uB UNIQUEIDENTIFIER, @uT UNIQUEIDENTIFIER, @docG1 UNIQUEIDENTIFIER;

SELECT TOP 1 @asig = a.idAsignatura, @g1 = a.idGrupo, @eA = a.idEstudiante, @uA = a.idUsuario,
             @g2 = b.idGrupo, @eB = b.idEstudiante, @uB = b.idUsuario
FROM dbo.uv_materia_estudiante a
INNER JOIN dbo.uv_materia_estudiante b ON b.idAsignatura = a.idAsignatura AND b.idGrupo <> a.idGrupo AND b.idEstudiante <> a.idEstudiante
WHERE a.codigoEstadoEstudiante = @inscrita AND b.codigoEstadoEstudiante = @inscrita
  AND NOT EXISTS (SELECT 1 FROM dbo.uv_materia_estudiante x WHERE x.idEstudiante = a.idEstudiante AND x.idGrupo = b.idGrupo)
  AND NOT EXISTS (SELECT 1 FROM dbo.uv_materia_estudiante x WHERE x.idEstudiante = b.idEstudiante AND x.idGrupo = a.idGrupo)
  AND (SELECT COUNT(*) FROM dbo.uv_materia_estudiante x WHERE x.idEstudiante = a.idEstudiante) = 1
  AND (SELECT COUNT(*) FROM dbo.uv_materia_estudiante x WHERE x.idEstudiante = b.idEstudiante) = 1
ORDER BY a.idGrupo, a.idEstudiante, b.idGrupo;
SELECT @docG1 = g.docente, @uT = d.usuario FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente WHERE g.id = @g1;

IF @asig IS NULL OR @g1 IS NULL OR @g2 IS NULL OR @uA IS NULL OR @uB IS NULL OR @uT IS NULL
    THROW 56300, 'TEST FAILED: W2B fixture: se requieren dos estudiantes inscritos en grupos distintos de la misma asignatura (semilla LB-004D).', 1;

DECLARE @corr UNIQUEIDENTIFIER, @ok BIT, @errNum INT, @errMsg NVARCHAR(4000), @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @inscrita);
DECLARE @base DATETIME2(7) = DATEADD(DAY, -40, CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2(7)));
DECLARE @n1 INT = 100 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @g1);
DECLARE @n2 INT = 200 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @g2);
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID(), @s3 UNIQUEIDENTIFIER = NEWID(), @s4 UNIQUEIDENTIFIER = NEWID(),
        @s5 UNIQUEIDENTIFIER = NEWID(), @s6 UNIQUEIDENTIFIER = NEWID(), @s7 UNIQUEIDENTIFIER = NEWID(), @s8 UNIQUEIDENTIFIER = NEWID(),
        @sFalta UNIQUEIDENTIFIER = NEWID();
DECLARE @total INT, @esperadoG1 INT, @esperadoG2 INT, @pagina INT, @tam INT = 3, @filas INT;

CREATE TABLE #w2b_sm (pos INT IDENTITY(1,1), id UNIQUEIDENTIFIER, nombre NVARCHAR(250), numero INT, codigo NVARCHAR(50), numeroSemana INT,
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    fechaLimiteJustificacionUtc DATETIME2(7), plazoJustificacionVigente BIT, totalRegistros INT);
CREATE TABLE #w2b_pg (pos INT IDENTITY(1,1), id UNIQUEIDENTIFIER, nombre NVARCHAR(250), numero INT, codigo NVARCHAR(50), numeroSemana INT,
    idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    fechaLimiteJustificacionUtc DATETIME2(7), plazoJustificacionVigente BIT, totalRegistros INT);
CREATE TABLE #w2b_l (idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(250), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(100), creditos INT);
CREATE TABLE #w2b_r (totalMaterias INT, materiasEnRiesgo INT NULL, totalHorasFalta DECIMAL(12,2), totalCreditos INT);
CREATE TABLE #w2b_rv (idEstudianteGrupo UNIQUEIDENTIFIER, codigoPermanencia NVARCHAR(10) NULL, horasFalta DECIMAL(12,6));

BEGIN TRANSACTION;
BEGIN TRY
    -- A se inscribe tambien en el grupo de B (misma asignatura): dos materias (asignatura y grupo)
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (NEWID(), @estA, @eA, @g2);

    -- Sesiones del grupo 1 con el numero DESORDENADO respecto del inicio; s3 y s4 comparten inicio (desempata el numero)
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal) VALUES
        (@s1, N'QA W2B 1', @n1,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 5, @base), DATEADD(HOUR, 1, DATEADD(DAY, 5, @base)), N'UTC_V2'),
        (@s2, N'QA W2B 2', @n1 + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 1, @base), DATEADD(HOUR, 1, DATEADD(DAY, 1, @base)), N'UTC_V2'),
        (@s3, N'QA W2B 3', @n1 + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 3, @base), DATEADD(HOUR, 1, DATEADD(DAY, 3, @base)), N'UTC_V2'),
        (@s4, N'QA W2B 4', @n1 + 3, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 3, @base), DATEADD(HOUR, 1, DATEADD(DAY, 3, @base)), N'UTC_V2'),
        (@s5, N'QA W2B 5', @n1 + 4, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 2, @base), DATEADD(HOUR, 1, DATEADD(DAY, 2, @base)), N'UTC_V2'),
        (@s6, N'QA W2B 6', @n1 + 5, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 6, @base), DATEADD(HOUR, 1, DATEADD(DAY, 6, @base)), N'UTC_V2'),
        (@sFalta, N'QA W2B falta', @n1 + 6, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g1, DATEADD(DAY, 7, @base), DATEADD(HOUR, 1, DATEADD(DAY, 7, @base)), N'UTC_V2');
    -- Sesiones del grupo 2: s7 repite numero e inicio de s3 (desempata el identificador); s8 inicia antes que s2
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal) VALUES
        (@s7, N'QA W2B 7', @n1 + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g2, DATEADD(DAY, 3, @base), DATEADD(HOUR, 1, DATEADD(DAY, 3, @base)), N'UTC_V2'),
        (@s8, N'QA W2B 8', @n2 + 50, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g2, DATEADD(DAY, 0, @base), DATEADD(HOUR, 1, DATEADD(DAY, 0, @base)), N'UTC_V2');
    SELECT @esperadoG1 = COUNT(*) FROM dbo.Sesion WHERE grupo = @g1;
    SELECT @esperadoG2 = COUNT(*) FROM dbo.Sesion WHERE grupo = @g2;

    -- Una falta sin justa causa de A en la sesion @sFalta (1 h): el grupo 1 queda con 100 % de inasistencia y el grupo 2 sin registro
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, 1, (SELECT TOP 1 m.id FROM dbo.ModoTomaAsistencia m WHERE m.usaCodigoQr = 0),
           (SELECT TOP 1 e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0), 0, @docG1,
           CAST(s.fechaHoraInicio AS DATETIME2(0)), CAST(s.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM dbo.Sesion s WHERE s.id = @sFalta;
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT NEWID(), eg.id, @sFalta FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = @eA AND eg.grupo = @g1;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, (SELECT id FROM dbo.RazonCausa WHERE codigo = N'SJC'),
           se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM dbo.Asistencia a INNER JOIN dbo.Sesion se ON se.id = a.sesion INNER JOIN dbo.TomaAsistencia t ON t.sesion = a.sesion AND t.numero = 1
    WHERE a.sesion = @sFalta;

    -- ======================================================= W2B_SES: orden determinista y paginas
    SET @corr = NEWID();
    INSERT INTO #w2b_sm (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100;
    SET @total = @esperadoG1 + @esperadoG2;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_sm) = @total
                  AND NOT EXISTS (SELECT 1 FROM #w2b_sm x INNER JOIN #w2b_sm y ON y.pos = x.pos + 1
                                  WHERE NOT (x.fechaHoraInicio < y.fechaHoraInicio
                                             OR (x.fechaHoraInicio = y.fechaHoraInicio AND (x.numero < y.numero
                                                 OR (x.numero = y.numero AND x.id < y.id))))), 1, 0);
    EXEC #w2b_expect 'SES_01_ORDEN_CRONOLOGICO', @ok;
    -- la prueba es significativa: por numero el orden seria otro (s1 tiene un numero menor que s2 pero inicia despues)
    SET @ok = IIF((SELECT pos FROM #w2b_sm WHERE id = @s2) < (SELECT pos FROM #w2b_sm WHERE id = @s1)
                  AND (SELECT pos FROM #w2b_sm WHERE id = @s5) < (SELECT pos FROM #w2b_sm WHERE id = @s3)
                  AND (SELECT pos FROM #w2b_sm WHERE id = @s3) < (SELECT pos FROM #w2b_sm WHERE id = @s4)
                  AND (SELECT pos FROM #w2b_sm WHERE id = @s8) < (SELECT pos FROM #w2b_sm WHERE id = @s2), 1, 0);
    EXEC #w2b_expect 'SES_01_ORDEN_SIGNIFICATIVO', @ok;
    PRINT 'TEST_PASS:W2B_SES_01_ORDEN_CRONOLOGICO';

    -- desempate por identificador: s3 (grupo 1) y s7 (grupo 2) tienen igual inicio y numero; salen adyacentes y por id
    SET @ok = IIF((SELECT numero FROM #w2b_sm WHERE id = @s3) = (SELECT numero FROM #w2b_sm WHERE id = @s7)
                  AND (SELECT fechaHoraInicio FROM #w2b_sm WHERE id = @s3) = (SELECT fechaHoraInicio FROM #w2b_sm WHERE id = @s7)
                  AND ABS((SELECT pos FROM #w2b_sm WHERE id = @s3) - (SELECT pos FROM #w2b_sm WHERE id = @s7)) = 1
                  AND ((@s3 < @s7 AND (SELECT pos FROM #w2b_sm WHERE id = @s3) < (SELECT pos FROM #w2b_sm WHERE id = @s7))
                       OR (@s7 < @s3 AND (SELECT pos FROM #w2b_sm WHERE id = @s7) < (SELECT pos FROM #w2b_sm WHERE id = @s3))), 1, 0);
    EXEC #w2b_expect 'SES_02_DESEMPATE_POR_ID', @ok;
    PRINT 'TEST_PASS:W2B_SES_02_DESEMPATE_POR_ID';

    -- paginas de 3: la union de todas las paginas es la lista completa, en el mismo orden, sin repetir ni saltar, con el total constante
    SET @pagina = 1;
    WHILE @pagina <= CEILING(@total / CAST(@tam AS FLOAT)) + 1
    BEGIN
        SET @corr = NEWID();
        INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                         fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
        EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
            @numeroPagina = @pagina, @tamanoPagina = @tam;
        SET @pagina += 1;
    END
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_pg) = @total
                  AND (SELECT COUNT(DISTINCT id) FROM #w2b_pg) = @total
                  AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE totalRegistros <> @total)
                  AND NOT EXISTS (SELECT 1 FROM #w2b_sm s INNER JOIN #w2b_pg p ON p.pos = s.pos WHERE p.id <> s.id), 1, 0);
    EXEC #w2b_expect 'SES_03_PAGINAS_SIN_REPETIR_NI_SALTAR', @ok;
    -- una pagina mas alla de la ultima no trae filas (la ultima del bucle ya lo cubre: se contaron exactamente @total)
    SET @corr = NEWID();
    SET @filas = (SELECT COUNT(*) FROM #w2b_pg);
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 99, @tamanoPagina = @tam;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_pg) = @filas, 1, 0);
    EXEC #w2b_expect 'SES_03_PAGINA_FUERA_DE_RANGO_VACIA', @ok;
    PRINT 'TEST_PASS:W2B_SES_03_PAGINAS';

    -- filtro opcional por grupo: solo ese grupo y su total; NULL = todos los grupos inscritos
    DELETE FROM #w2b_pg;
    SET @corr = NEWID();
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @g2;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_pg) = @esperadoG2 AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE idGrupo <> @g2 OR totalRegistros <> @esperadoG2)
                  AND EXISTS (SELECT 1 FROM #w2b_pg WHERE id = @s7) AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE id = @s1), 1, 0);
    EXEC #w2b_expect 'SES_04_FILTRO_GRUPO_2', @ok;
    DELETE FROM #w2b_pg;
    SET @corr = NEWID();
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @g1;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_pg) = @esperadoG1 AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE idGrupo <> @g1 OR totalRegistros <> @esperadoG1), 1, 0);
    EXEC #w2b_expect 'SES_04_FILTRO_GRUPO_1', @ok;
    -- un grupo desconocido o en el que el estudiante no esta inscrito no devuelve filas (igual que una materia ajena)
    DELETE FROM #w2b_pg;
    SET @corr = NEWID();
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @sFalta;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #w2b_pg), 1, 0);
    EXEC #w2b_expect 'SES_04_GRUPO_DESCONOCIDO_CERO_FILAS', @ok;
    PRINT 'TEST_PASS:W2B_SES_04_FILTRO_GRUPO';

    -- aislamiento: B solo ve las sesiones de su grupo; con el grupo de A no obtiene filas
    DELETE FROM #w2b_pg;
    SET @corr = NEWID();
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uB, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_pg) = @esperadoG2 AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE idGrupo <> @g2)
                  AND NOT EXISTS (SELECT 1 FROM #w2b_pg WHERE id IN (@s1, @s2, @s3, @s4, @s5, @s6, @sFalta)), 1, 0);
    EXEC #w2b_expect 'SES_05_AISLAMIENTO_B_SOLO_SU_GRUPO', @ok;
    DELETE FROM #w2b_pg;
    SET @corr = NEWID();
    INSERT INTO #w2b_pg (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                     fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
    EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uB, @idCorrelacion = @corr, @idMateria = @asig,
        @numeroPagina = 1, @tamanoPagina = 100, @idGrupo = @g1;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #w2b_pg), 1, 0);
    EXEC #w2b_expect 'SES_05_AISLAMIENTO_B_GRUPO_AJENO', @ok;
    PRINT 'TEST_PASS:W2B_SES_05_AISLAMIENTO';

    -- ======================================================= W2B_RES: resumen coherente con el listado
    SET @corr = NEWID();
    INSERT INTO #w2b_l EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_l) = 2
                  AND (SELECT COUNT(*) FROM #w2b_r) = 1
                  AND (SELECT totalMaterias FROM #w2b_r) = (SELECT COUNT(*) FROM #w2b_l)
                  AND (SELECT totalCreditos FROM #w2b_r) = (SELECT ISNULL(SUM(creditos), 0) FROM #w2b_l), 1, 0);
    EXEC #w2b_expect 'RES_01_COHERENTE_CON_EL_LISTADO', @ok;
    PRINT 'TEST_PASS:W2B_RES_01_COHERENCIA_CON_LISTADO';

    -- horas de falta y materias en riesgo contra la vista de resumen de asistencia (misma regla y umbrales que las alertas)
    INSERT INTO #w2b_rv (idEstudianteGrupo, codigoPermanencia, horasFalta)
    SELECT r.idEstudianteGrupo, r.codigoPermanencia, r.horasFalta
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_materia_estudiante m ON m.idEstudianteGrupo = r.idEstudianteGrupo
    WHERE m.idUsuario = @uA AND m.codigoEstadoEstudiante = @inscrita;
    SET @ok = IIF((SELECT materiasEnRiesgo FROM #w2b_r) = 1
                  AND (SELECT materiasEnRiesgo FROM #w2b_r) = (SELECT COUNT(*) FROM #w2b_rv WHERE codigoPermanencia IN (N'RIESGO', N'PERDIDA'))
                  AND (SELECT totalHorasFalta FROM #w2b_r) = 1.00
                  AND (SELECT totalHorasFalta FROM #w2b_r) = (SELECT SUM(ROUND(horasFalta, 2)) FROM #w2b_rv)
                  AND EXISTS (SELECT 1 FROM #w2b_rv WHERE codigoPermanencia = N'PERDIDA' AND horasFalta = 1.0)
                  AND EXISTS (SELECT 1 FROM #w2b_rv WHERE codigoPermanencia = N'REGULAR' AND horasFalta = 0), 1, 0);
    EXEC #w2b_expect 'RES_02_RIESGO_Y_HORAS_DE_FALTA', @ok;
    PRINT 'TEST_PASS:W2B_RES_02_RIESGO_Y_HORAS_DE_FALTA';

    -- el umbral es del catalogo: con advertencia 0 toda materia queda en riesgo; con umbrales altos ninguna; sin umbral, sin dato
    UPDATE dbo.CatalogoParametro SET valor = N'0', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'100', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT materiasEnRiesgo FROM #w2b_r) = (SELECT totalMaterias FROM #w2b_r) AND (SELECT totalMaterias FROM #w2b_r) = 2, 1, 0);
    EXEC #w2b_expect 'RES_03_UMBRAL_DEL_CATALOGO_TODAS_EN_RIESGO', @ok;
    UPDATE dbo.CatalogoParametro SET valor = N'200' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'300' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT materiasEnRiesgo FROM #w2b_r) = 0 AND (SELECT totalMaterias FROM #w2b_r) = 2, 1, 0);
    EXEC #w2b_expect 'RES_03_UMBRAL_DEL_CATALOGO_NINGUNA_EN_RIESGO', @ok;
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT materiasEnRiesgo FROM #w2b_r) IS NULL AND (SELECT totalMaterias FROM #w2b_r) = 2 AND (SELECT totalHorasFalta FROM #w2b_r) = 1.00, 1, 0);
    EXEC #w2b_expect 'RES_03_SIN_UMBRAL_ES_SIN_DATO', @ok;
    UPDATE dbo.CatalogoParametro SET valor = N'15', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'20', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    PRINT 'TEST_PASS:W2B_RES_03_UMBRAL_DEL_CATALOGO';

    -- solo la matricula inscrita cuenta, igual que en el listado: la del grupo 2 pasa a retirada (I) y sale de las dos consultas
    UPDATE dbo.EstudianteGrupo SET estado = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I')
    WHERE estudiante = @eA AND grupo = @g2;
    DELETE FROM #w2b_l; DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_l EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_l) = 1 AND (SELECT totalMaterias FROM #w2b_r) = 1
                  AND (SELECT totalCreditos FROM #w2b_r) = (SELECT ISNULL(SUM(creditos), 0) FROM #w2b_l)
                  AND (SELECT materiasEnRiesgo FROM #w2b_r) = 1, 1, 0);
    EXEC #w2b_expect 'RES_04_SOLO_MATRICULA_INSCRITA', @ok;
    -- un estudiante sin ninguna matricula inscrita: cero materias, cero horas, cero creditos y cero en riesgo (no NULL)
    UPDATE dbo.EstudianteGrupo SET estado = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I')
    WHERE estudiante = @eA AND grupo = @g1;
    DELETE FROM #w2b_l; DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_l EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #w2b_l) = 0 AND (SELECT COUNT(*) FROM #w2b_r) = 1 AND (SELECT totalMaterias FROM #w2b_r) = 0
                  AND (SELECT materiasEnRiesgo FROM #w2b_r) = 0 AND (SELECT totalHorasFalta FROM #w2b_r) = 0
                  AND (SELECT totalCreditos FROM #w2b_r) = 0, 1, 0);
    EXEC #w2b_expect 'RES_04_SIN_MATERIAS_CEROS', @ok;
    PRINT 'TEST_PASS:W2B_RES_04_SOLO_MATRICULA_INSCRITA';

    -- aislamiento: B ve solo lo suyo (una materia, sin horas de falta ni riesgo) aunque A tenga faltas
    DELETE FROM #w2b_l; DELETE FROM #w2b_r;
    SET @corr = NEWID();
    INSERT INTO #w2b_l EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uB, @idCorrelacion = @corr;
    INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uB, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT totalMaterias FROM #w2b_r) = (SELECT COUNT(*) FROM #w2b_l) AND (SELECT COUNT(*) FROM #w2b_l) = 1
                  AND (SELECT totalHorasFalta FROM #w2b_r) = 0 AND (SELECT materiasEnRiesgo FROM #w2b_r) = 0
                  AND (SELECT totalCreditos FROM #w2b_r) = (SELECT ISNULL(SUM(creditos), 0) FROM #w2b_l), 1, 0);
    EXEC #w2b_expect 'RES_05_AISLAMIENTO_B_SOLO_LO_SUYO', @ok;
    PRINT 'TEST_PASS:W2B_RES_05_AISLAMIENTO';

    -- permiso minimo del runtime
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.database_permissions dp
                          WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_resumen_materias_estudiante') AND dp.permission_name = N'EXECUTE'
                            AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')), 1, 0);
    EXEC #w2b_expect 'RES_06_PERMISO_DEL_RUNTIME', @ok;
    PRINT 'TEST_PASS:W2B_RES_06_PERMISO_RUNTIME';

    ROLLBACK TRANSACTION;

    -- Rechazos (THROW 51000 con XACT_ABORT ON: fuera de la transaccion de la prueba)
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = @uT, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@errNum = 51000, 1, 0);
    EXEC #w2b_expect 'RES_06_NO_ESTUDIANTE_RECHAZADO', @ok;
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT INTO #w2b_r EXEC dbo.usp_consultar_resumen_materias_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @corr;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
        SET @errMsg = ERROR_MESSAGE();
    END CATCH
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    SET @ok = IIF(@errNum = 51000 AND LEFT(@errMsg, LEN(@techMsg)) = @techMsg, 1, 0);
    EXEC #w2b_expect 'RES_06_EJECUTOR_NULO_GEN_002', @ok;
    SET @errNum = NULL;
    BEGIN TRY
        SET @corr = NEWID();
        INSERT INTO #w2b_sm (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                         fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
        EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uA, @idCorrelacion = @corr, @idMateria = @asig,
            @numeroPagina = 1, @tamanoPagina = 0, @idGrupo = @g1;
    END TRY
    BEGIN CATCH
        SET @errNum = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@errNum = 51000, 1, 0);
    EXEC #w2b_expect 'SES_05_PAGINACION_INVALIDA_SIGUE_RECHAZADA', @ok;
    PRINT 'TEST_PASS:W2B_RES_06_RECHAZOS';
END TRY
BEGIN CATCH
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #w2b_sm; DROP TABLE IF EXISTS #w2b_pg; DROP TABLE IF EXISTS #w2b_l; DROP TABLE IF EXISTS #w2b_r; DROP TABLE IF EXISTS #w2b_rv;
    THROW 56302, @fallo, 1;
END CATCH
DROP TABLE IF EXISTS #w2b_sm; DROP TABLE IF EXISTS #w2b_pg; DROP TABLE IF EXISTS #w2b_l; DROP TABLE IF EXISTS #w2b_r; DROP TABLE IF EXISTS #w2b_rv;
IF @@TRANCOUNT <> 0 THROW 56303, 'TEST FAILED W2B_TRANCOUNT_ZERO: la prueba dejo una transaccion abierta.', 1;
PRINT 'TEST_PASS:W2B_TRANCOUNT_ZERO';
GO
