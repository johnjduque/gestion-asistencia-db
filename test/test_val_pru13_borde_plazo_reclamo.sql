USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- VAL-pendientes-john PRU-13: borde EXACTO del plazo de reclamo/justificacion (HU026B, CULM-001 D.1). Solo pruebas: sin cambio de logica.
--   limite (exclusivo, UTC) = medianoche local (TIEMPO/ZONA_HORARIA_SQLSERVER) del dia  fecha-local-de-fin + N + 1,
--   N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION; se admite mientras SYSUTCDATETIME() < limite.
-- El reloj del motor no se puede fijar, asi que el borde se prueba en las dos dimensiones que si se controlan:
--   * la funcion (entradas fijas): el ultimo minuto valido es 23:59 local del ultimo dia y el primero vencido es 00:00 local del
--     dia siguiente; una sesion que termina 23:59:59 local y otra que termina 00:00 local (un instante despues, mismo dia UTC)
--     tienen limites separados por un dia; con la zona del parametro en UTC el corte del dia se mueve con la zona.
--   * el SP real (usp_radicar_solicitud_revision_asistencia_v3 con el reloj real): la sesion que termino a las 00:00 locales de
--     hoy-N es la mas antigua que hoy todavia se admite (su ultimo minuto valido es hoy 23:59 local) y la que termino a las 23:59:59
--     locales de hoy-N-1 es la mas reciente que ya vencio (su limite fue hoy 00:00 local: REV_020 con el ultimo dia = ayer).
--     Se repite con N = 0, N = 1 y el N de la semilla (parametro editable).
--   VAL_PRU13_01_FN_ULTIMO_MINUTO_LOCAL      23:59 local admitido, 00:00 local vencido (ejemplo del contrato, N de la semilla y N = 0)
--   VAL_PRU13_02_FN_FRONTERA_DIA_LOCAL       fin 23:59:59.9999999 vs 00:00:00 locales: limites a un dia; con zona UTC, el corte cambia
--   VAL_PRU13_03_SP_ULTIMO_MINUTO_VALIDO     radicacion admitida y limite = manana 00:00 local (N = 0, 1 y semilla)
--   VAL_PRU13_04_SP_PRIMER_MINUTO_VENCIDO    REV_020, sin escrituras, ultimo dia = ayer y limite = hoy 00:00 local (N = 0, 1 y semilla)
--   VAL_PRU13_TRANCOUNT_ZERO
-- Todo dentro de una transaccion revertida: no deja datos ni cambia parametros.
-- ============================================================================
PRINT 'TEST START: test_val_pru13_borde_plazo_reclamo (PRU-13, borde exacto del plazo)';
IF OBJECT_ID('tempdb..#pru13_expect') IS NOT NULL DROP PROCEDURE #pru13_expect;
GO
CREATE PROCEDURE #pru13_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: VAL_PRU13_', @label);
        THROW 52350, @mensaje, 1;
    END
END;
GO

DECLARE @tz NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
DECLARE @nSemilla INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
DECLARE @codInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @userS UNIQUEIDENTIFIER;

SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante
FROM dbo.uv_estudiante_grupo eg
WHERE eg.codigoEstadoEstudiante = @codInscrita
ORDER BY eg.idGrupo, eg.idEstudiante;
SELECT @userS = usuario FROM dbo.Estudiante WHERE id = @student;

IF @group IS NULL OR @student IS NULL OR @userS IS NULL OR @tz IS NULL OR @tz = N'' OR @nSemilla IS NULL OR @nSemilla < 0
    THROW 52351, 'TEST FAILED: VAL_PRU13 fixture o parametros faltantes (semilla local).', 1;

DECLARE @limite DATETIME2(7), @limite2 DATETIME2(7), @ok BIT, @corr UNIQUEIDENTIFIER, @n INT, @i INT;
DECLARE @hoyLocal DATE, @finValido DATETIME2(7), @finVencido DATETIME2(7), @sValida UNIQUEIDENTIFIER, @sVencida UNIQUEIDENTIFIER;
DECLARE @num INT, @filasAntes INT, @filasDespues INT, @limiteValida DATETIME2(7), @limiteVencida DATETIME2(7);
DECLARE @descU NVARCHAR(4000), @descT NVARCHAR(4000), @descE BIT, @ultimoDiaEsperado NVARCHAR(10);
DECLARE @valoresN TABLE (orden INT IDENTITY(1, 1), n INT);
INSERT INTO @valoresN (n) VALUES (0), (1), (@nSemilla);

DROP TABLE IF EXISTS #pru13;
CREATE TABLE #pru13 (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL, idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL);

BEGIN TRANSACTION;
BEGIN TRY
    -- ---------------------------------------------------------------- 01 funcion: ultimo minuto valido contra primer minuto vencido
    -- Fin 2026-11-04 08:00 Bogota (13:00 UTC). Con N de la semilla el limite es la medianoche local del dia fin + N + 1: un minuto antes
    -- es 23:59 local del ultimo dia admitido (se admite: instante < limite) y el limite mismo es 00:00 local (ya vencido: instante >= limite).
    SET @limite = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-04T13:00:00');
    SET @ok = IIF(CAST(DATEADD(MINUTE, -1, @limite) AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0))
                      = DATEADD(MINUTE, 23 * 60 + 59, CAST(DATEADD(DAY, @nSemilla, CAST('2026-11-04' AS DATE)) AS DATETIME2(0)))
                  AND CAST(@limite AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0))
                      = CAST(DATEADD(DAY, @nSemilla + 1, CAST('2026-11-04' AS DATE)) AS DATETIME2(0))
                  AND DATEADD(MINUTE, -1, @limite) < @limite
                  AND (@nSemilla <> 5 OR @tz <> N'SA Pacific Standard Time' OR @limite = '2026-11-10T05:00:00'), 1, 0);
    EXEC #pru13_expect '01_FN_ULTIMO_MINUTO_LOCAL', @ok;
    -- N = 0: el reclamo solo se admite el mismo dia local de la sesion (hasta 23:59 local); a las 00:00 locales ya vencio.
    UPDATE dbo.CatalogoParametro SET valor = N'0' WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    SET @limite = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-04T13:00:00');
    SET @ok = IIF(CAST(@limite AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0)) = '2026-11-05T00:00:00'
                  AND CAST(DATEADD(MINUTE, -1, @limite) AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0)) = '2026-11-04T23:59:00'
                  AND (@tz <> N'SA Pacific Standard Time' OR @limite = '2026-11-05T05:00:00'), 1, 0);
    EXEC #pru13_expect '01_FN_ULTIMO_MINUTO_LOCAL_N0', @ok;
    UPDATE dbo.CatalogoParametro SET valor = CAST(@nSemilla AS NVARCHAR(20)) WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    PRINT 'TEST_PASS:VAL_PRU13_01_FN_ULTIMO_MINUTO_LOCAL';

    -- ---------------------------------------------------------------- 02 funcion: frontera del dia LOCAL (no del dia UTC)
    -- 2026-11-05 04:59:59.9999999 UTC es 2026-11-04 23:59:59.9999999 en Bogota y 05:00:00 UTC es 2026-11-05 00:00 en Bogota: el mismo dia
    -- UTC, pero dias locales distintos, asi que sus limites quedan a un dia exacto.
    SET @limite = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-05T04:59:59.9999999');
    SET @limite2 = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-05T05:00:00');
    SET @ok = IIF(@tz <> N'SA Pacific Standard Time'
                  OR (DATEDIFF(DAY, @limite, @limite2) = 1
                      AND @limite = CAST(CAST(DATEADD(DAY, @nSemilla + 1, CAST('2026-11-04' AS DATE)) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7))
                      AND @limite2 = CAST(CAST(DATEADD(DAY, @nSemilla + 1, CAST('2026-11-05' AS DATE)) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7))), 1, 0);
    EXEC #pru13_expect '02_FN_FRONTERA_DIA_LOCAL', @ok;
    -- La zona tambien es parametro: en UTC los dos instantes caen el mismo dia (2026-11-05) y comparten limite (medianoche UTC).
    UPDATE dbo.CatalogoParametro SET valor = N'UTC' WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER';
    SET @limite = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-05T04:59:59.9999999');
    SET @limite2 = dbo.ufn_calcular_fecha_limite_justificacion('2026-11-05T05:00:00');
    SET @ok = IIF(@limite = @limite2 AND @limite = CAST(DATEADD(DAY, @nSemilla + 1, CAST('2026-11-05' AS DATE)) AS DATETIME2(7)), 1, 0);
    EXEC #pru13_expect '02_FN_FRONTERA_DIA_ZONA_PARAMETRO', @ok;
    UPDATE dbo.CatalogoParametro SET valor = @tz WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER';
    PRINT 'TEST_PASS:VAL_PRU13_02_FN_FRONTERA_DIA_LOCAL';

    -- ---------------------------------------------------------------- 03 y 04: el SP real con el reloj real, para N = 0, 1 y el de la semilla
    SET @i = 1;
    WHILE @i <= (SELECT MAX(orden) FROM @valoresN)
    BEGIN
        SELECT @n = n FROM @valoresN WHERE orden = @i;
        UPDATE dbo.CatalogoParametro SET valor = CAST(@n AS NVARCHAR(20)) WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';

        SET @hoyLocal = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @tz AS DATE);
        -- Sesion que termina a las 00:00:00 locales de hoy-N (la mas antigua que hoy todavia se puede reclamar)
        SET @finValido = CAST(CAST(CAST(DATEADD(DAY, -@n, @hoyLocal) AS DATETIME2(7)) AS DATETIME2(7)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2(7));
        -- Sesion que termina a las 23:59:59.9999999 locales de hoy-N-1 (un instante antes: la mas reciente que ya vencio)
        SET @finVencido = DATEADD(NANOSECOND, -100, @finValido);
        SET @sValida = NEWID();
        SET @sVencida = NEWID();
        SET @num = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
        INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
            (@sValida,  CONCAT(N'QA PRU13 valida N', @n),  @num,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finValido),  @finValido),
            (@sVencida, CONCAT(N'QA PRU13 vencida N', @n), @num + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finVencido), @finVencido);

        -- 03: ultimo minuto valido. El limite es manana 00:00 local, asi que hoy 23:59 local todavia se admite y la radicacion pasa.
        SET @limiteValida = NULL;
        SELECT @descU = N'', @descT = N'', @descE = 1;
        EXEC dbo.usp_validar_plazo_justificacion_interno @idSesion = @sValida, @idCorrelacion = NULL, @fechaLimiteUtc = @limiteValida OUTPUT,
            @mensajeUsuarioResultado = @descU OUTPUT, @mensajeTecnicoResultado = @descT OUTPUT, @estadoResultado = @descE OUTPUT;
        TRUNCATE TABLE #pru13;
        SET @corr = NEWID();
        INSERT INTO #pru13 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @student, @idSesion = @sValida,
            @categoria = N'CAL', @justificacion = N'QA PRU13 ultimo minuto valido', @idsArchivoSoporte = NULL,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @userS;
        SET @ok = IIF(@descE = 1
                      AND CAST(@limiteValida AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0)) = CAST(DATEADD(DAY, 1, @hoyLocal) AS DATETIME2(0))
                      AND CAST(DATEADD(MINUTE, -1, @limiteValida) AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0))
                          = DATEADD(MINUTE, 23 * 60 + 59, CAST(@hoyLocal AS DATETIME2(0)))
                      AND SYSUTCDATETIME() < @limiteValida
                      AND EXISTS (SELECT 1 FROM #pru13 WHERE idCorrelacion = @corr AND estadoResultado = 1 AND idSolicitudRevision IS NOT NULL)
                      AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
                                  WHERE a.sesion = @sValida AND r.justificacionSolicitud = N'QA PRU13 ultimo minuto valido')
                      AND @@TRANCOUNT = 1, 1, 0);
        EXEC #pru13_expect '03_SP_ULTIMO_MINUTO_VALIDO', @ok;

        -- 04: primer minuto vencido. El limite fue hoy 00:00 local (ultimo minuto valido: ayer 23:59 local): REV_020 sin escrituras.
        SET @limiteVencida = NULL;
        SELECT @descU = N'', @descT = N'', @descE = 1;
        EXEC dbo.usp_validar_plazo_justificacion_interno @idSesion = @sVencida, @idCorrelacion = NULL, @fechaLimiteUtc = @limiteVencida OUTPUT,
            @mensajeUsuarioResultado = @descU OUTPUT, @mensajeTecnicoResultado = @descT OUTPUT, @estadoResultado = @descE OUTPUT;
        SET @ultimoDiaEsperado = CONVERT(NVARCHAR(10), DATEADD(DAY, -1, @hoyLocal), 23);
        SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
        TRUNCATE TABLE #pru13;
        SET @corr = NEWID();
        INSERT INTO #pru13 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @student, @idSesion = @sVencida,
            @categoria = N'CAL', @justificacion = N'QA PRU13 primer minuto vencido', @idsArchivoSoporte = NULL,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @userS;
        SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
        SET @ok = IIF(@descE = 0
                      AND CAST(@limiteVencida AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0)) = CAST(@hoyLocal AS DATETIME2(0))
                      AND CAST(DATEADD(MINUTE, -1, @limiteVencida) AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATETIME2(0))
                          = DATEADD(MINUTE, 23 * 60 + 59, CAST(DATEADD(DAY, -1, @hoyLocal) AS DATETIME2(0)))
                      AND DATEDIFF(DAY, @limiteVencida, @limiteValida) = 1
                      AND SYSUTCDATETIME() >= @limiteVencida
                      AND EXISTS (SELECT 1 FROM #pru13 WHERE idCorrelacion = @corr AND estadoResultado = 0 AND idSolicitudRevision IS NULL
                                  AND mensajeTecnicoResultado LIKE N'DBCODE=REV[_]020|%'
                                  AND mensajeUsuarioResultado = CONCAT(N'El plazo para justificar esta inasistencia venció el ', @ultimoDiaEsperado, N'.'))
                      AND @filasAntes = @filasDespues
                      AND @@TRANCOUNT = 1, 1, 0);
        EXEC #pru13_expect '04_SP_PRIMER_MINUTO_VENCIDO', @ok;

        SET @i += 1;
    END
    UPDATE dbo.CatalogoParametro SET valor = CAST(@nSemilla AS NVARCHAR(20)) WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION';
    PRINT 'TEST_PASS:VAL_PRU13_03_SP_ULTIMO_MINUTO_VALIDO';
    PRINT 'TEST_PASS:VAL_PRU13_04_SP_PRIMER_MINUTO_VENCIDO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #pru13;
    THROW 52352, @fallo, 1;
END CATCH
DROP TABLE IF EXISTS #pru13;
GO

IF @@TRANCOUNT = 0
    AND EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND valor <> N'UTC')
    AND NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre LIKE N'QA PRU13 %')
    PRINT 'TEST_PASS:VAL_PRU13_TRANCOUNT_ZERO';
ELSE
    THROW 52353, 'TEST FAILED: VAL_PRU13_TRANCOUNT_ZERO (transaccion abierta, parametro alterado o sesiones de prueba sin revertir).', 1;
GO
DROP PROCEDURE #pru13_expect;
GO
