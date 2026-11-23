USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- VAL PRU-13 / decision 3A (borde exacto del 20 %): la regla de perdida y de alertas se evalua DESPUES de redondear el porcentaje
-- a 2 decimales (ufn_calcular_porcentaje_inasistencia_horas, DECIMAL(5,2)); 19,995 % cuenta como 20,00 %. PRU-14 ya prueba las
-- funciones puras; aqui se prueba la integracion: la vista uv_resumen_asistencia_estudiante_grupo y el motor de alertas
-- (usp_evaluar_alertas_inasistencia_grupo) con datos reales de un grupo (fixture C: 25 sesiones, 1 estudiante con faltas).
--   VAL_UMBRAL_01_BORDE_20: justo debajo (19,99 %), en el redondeo (19,995 % -> 20,00 %), en (20,00 %) y justo encima (20,01 %) del
--                           umbral de perdida: la vista da el porcentaje redondeado y PERDIDA solo desde 20,00 %; el motor crea la
--                           alerta PERDIDA y la revision solo desde 20,00 % (con 19,99 % solo ADVERTENCIA y ninguna revision).
--   VAL_UMBRAL_02_BORDE_15: lo mismo con el umbral de advertencia (14,99 / 14,995 -> 15,00 / 15,00 / 15,01): la alerta ADVERTENCIA
--                           y la clasificacion RIESGO nacen desde 15,00 %; nunca una PERDIDA.
-- Las sesiones suman 20000 minutos (T) y las faltas F minutos: porcentaje = 100 * F / T (F = 2998 -> 14,99; 2999 -> 14,995; 3000;
-- 3002; 3998 -> 19,99; 3999 -> 19,995; 4000; 4002). Las horas de cada sesion son minutos/60 a 6 decimales, y para estas
-- distribuciones el redondeo de las horas deja 19,995000080 y 14,995000350 (sobre el empate), de modo que el redondeo comercial a
-- 2 decimales da 20,00 y 15,00. Los umbrales se fijan en 15 y 20 y todo corre dentro de una transaccion que siempre se revierte;
-- cada caso se deshace con un SAVE TRANSACTION.
PRINT 'TEST START: test_val_umbral_borde_alertas';
GO
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_fixture.sql
    IF OBJECT_ID(N'tempdb..#ub_ev') IS NOT NULL DROP TABLE #ub_ev;
    CREATE TABLE #ub_ev (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        alertasCreadas INT, alertasSuperadas INT, alertasReactivadas INT, revisionesCreadas INT, novedadesJSON NVARCHAR(MAX));
    DECLARE @rzSJC UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'SJC');
    DECLARE @rzAN  UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = N'AN');
    IF @rzSJC IS NULL OR @rzAN IS NULL THROW 58300, 'TEST FAILED: VAL_UMBRAL fixture: faltan las razones SJC/AN.', 1;

    UPDATE dbo.CatalogoParametro SET valor = N'15', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'20', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    UPDATE dbo.CatalogoParametro SET valor = N'true', estaActivo = 1 WHERE grupo = 'ALERTA_INASISTENCIA' AND clave = 'HABILITADA';

    -- caso, minutos de falta F, porcentaje esperado, permanencia esperada, alertas ADVERTENCIA / PERDIDA esperadas, revisiones esperadas
    DECLARE @casos TABLE (orden INT, caso VARCHAR(30), f INT, pctEsperado DECIMAL(5,2), permanencia NVARCHAR(10), adv INT, perd INT, rev INT);
    INSERT INTO @casos VALUES
        (1, 'P15_DEBAJO_14_99',        2998, 14.99, N'REGULAR', 0, 0, 0),
        (2, 'P15_REDONDEO_14_995',     2999, 15.00, N'RIESGO',  1, 0, 0),
        (3, 'P15_EXACTO_15_00',        3000, 15.00, N'RIESGO',  1, 0, 0),
        (4, 'P15_ENCIMA_15_01',        3002, 15.01, N'RIESGO',  1, 0, 0),
        (5, 'P20_DEBAJO_19_99',        3998, 19.99, N'RIESGO',  1, 0, 0),
        (6, 'P20_REDONDEO_19_995',     3999, 20.00, N'PERDIDA', 1, 1, 1),
        (7, 'P20_EXACTO_20_00',        4000, 20.00, N'PERDIDA', 1, 1, 1),
        (8, 'P20_ENCIMA_20_01',        4002, 20.01, N'PERDIDA', 1, 1, 1);
    DECLARE @orden INT = 1, @maxOrden INT = (SELECT MAX(orden) FROM @casos);
    DECLARE @caso VARCHAR(30), @f INT, @pctEsperado DECIMAL(5,2), @perm NVARCHAR(10), @adv INT, @perd INT, @rev INT;
    DECLARE @pct DECIMAL(5,2), @permReal NVARCHAR(10), @advReal INT, @perdReal INT, @revReal INT, @msg NVARCHAR(2000);
    WHILE @orden <= @maxOrden
    BEGIN
        SELECT @caso = caso, @f = f, @pctEsperado = pctEsperado, @perm = permanencia, @adv = adv, @perd = perd, @rev = rev FROM @casos WHERE orden = @orden;
        SAVE TRANSACTION sp_umbral_caso;

        -- Duraciones: sesiones 1..3 (falta SJC) reparten F minutos; sesiones 4..25 (asistencia AN) reparten 20000 - F minutos.
        -- Cada sesion conserva su inicio y su fin pasa a inicio + minutos (la toma queda dentro de la sesion).
        UPDATE se SET procedenciaTemporal = N'UTC_V2', fechaHoraFin = DATEADD(MINUTE,
                IIF(s.n <= 3, @f / 3 + IIF(s.n <= @f % 3, 1, 0), (20000 - @f) / 22 + IIF(s.n - 3 <= (20000 - @f) % 22, 1, 0)),
                se.fechaHoraInicio)
        FROM dbo.Sesion se INNER JOIN #c1s s ON s.idSesion = se.id;
        UPDATE da SET asistio = IIF(s.n <= 3, 0, 1), razonCausa = IIF(s.n <= 3, @rzSJC, @rzAN)
        FROM dbo.DetalleAsistencia da
        INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
        INNER JOIN #c1s s ON s.idSesion = a.sesion
        WHERE a.estudianteGrupo = @egEA;

        SELECT @pct = r.porcentajeInasistencia, @permReal = r.codigoPermanencia
        FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.idEstudianteGrupo = @egEA;
        IF @pct IS NULL OR @pct <> @pctEsperado OR ISNULL(@permReal, N'') <> @perm
        BEGIN
            SET @msg = CONCAT(N'TEST FAILED VAL_UMBRAL ', @caso, N': la vista dio ', ISNULL(CONVERT(VARCHAR(10), @pct), 'NULL'), N' % / ', ISNULL(@permReal, N'NULL'),
                              N' y se esperaba ', CONVERT(VARCHAR(10), @pctEsperado), N' % / ', @perm, N'.');
            THROW 58301, @msg, 1;
        END

        DELETE FROM #ub_ev;
        INSERT INTO #ub_ev EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @grupoG, @idCorrelacion = @c, @idEstudianteGrupo = @egEA;
        SELECT @advReal = COUNT(*) FROM dbo.uv_alerta_inasistencia WHERE idEstudianteGrupo = @egEA AND codigoTipo = N'ADVERTENCIA';
        SELECT @perdReal = COUNT(*) FROM dbo.uv_alerta_inasistencia WHERE idEstudianteGrupo = @egEA AND codigoTipo = N'PERDIDA';
        SELECT @revReal = COUNT(*) FROM dbo.RevisionCancelacion WHERE estudianteGrupo = @egEA;
        IF (SELECT estadoResultado FROM #ub_ev) <> 1 OR @advReal <> @adv OR @perdReal <> @perd OR @revReal <> @rev
        BEGIN
            SET @msg = CONCAT(N'TEST FAILED VAL_UMBRAL ', @caso, N': alertas ADVERTENCIA/PERDIDA/revisiones = ', @advReal, N'/', @perdReal, N'/', @revReal,
                              N' y se esperaba ', @adv, N'/', @perd, N'/', @rev, N' (', (SELECT mensajeTecnicoResultado FROM #ub_ev), N').');
            THROW 58302, @msg, 1;
        END

        ROLLBACK TRANSACTION sp_umbral_caso;
        IF @orden = 4 PRINT 'TEST_PASS:VAL_UMBRAL_02_BORDE_15';
        IF @orden = 8 PRINT 'TEST_PASS:VAL_UMBRAL_01_BORDE_20';
        SET @orden += 1;
    END
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msgC NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58399, @msgC, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58398, 'TEST FAILED: VAL_UMBRAL dejo una transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_UMBRAL_TRANCOUNT_ZERO';
GO
