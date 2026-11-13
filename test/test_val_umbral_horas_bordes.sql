USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- VAL PRU-14 (oleada 3): casos de borde de la regla del umbral de horas.
-- La regla vive en dos funciones que ya prueban, con el fixture de horas, los puntos 15.00 y 20.00 (CULM001_B2_HOR_05):
--   dbo.ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas): 100 * falta / dictadas, ROUND a 2 decimales,
--       acotado a [0, 100]; 0 si alguna entrada es NULL o <= 0.
--   dbo.ufn_clasificar_permanencia(porcentaje, estado): REGULAR < ADVERTENCIA <= RIESGO < PERDIDA <= PERDIDA, con los umbrales
--       ASISTENCIA/UMBRAL_ALERTA_ADVERTENCIA y ASISTENCIA/UMBRAL_ALERTA_PERDIDA; NULL si falta un umbral (nunca asume un valor).
--   dbo.ufn_umbral_alerta_inasistencia(idTipo): umbral del motor de alertas y del cierre; NULL si el parametro falta o no es numerico.
-- Casos:
--   VAL_PRU14_01: porcentaje en la frontera (19.99 / 20.00 / 20.01 sobre 100 h y sobre horas fraccionarias), cero, NULL y redondeo.
--   VAL_PRU14_02: clasificacion justo debajo, en y justo encima de cada umbral, con los umbrales fijados en 15 y 20.
--   VAL_PRU14_03: parametro ausente, inactivo o no numerico: la clasificacion y el umbral de alerta devuelven NULL.
--   VAL_PRU14_04: maximo: falta igual o mayor que lo dictado da 100.00; PERDIDA en su maximo editable (100) y valores extremos.
--   VAL_PRU14_05: la vista de resumen clasifica cada fila con la misma funcion y los umbrales vigentes (sin regla paralela).
-- Los casos que cambian parametros lo hacen dentro de una transaccion que siempre se revierte. Sin fixture propio: los
-- extremos de la regla son funciones puras y la integracion con datos reales ya la cubre test_culm001_b2_horas.sql.
PRINT 'TEST START: test_val_umbral_horas_bordes (VAL PRU-14)';
GO

-- --------------------------------------------------------------------------------------------------------------------
-- VAL_PRU14_01: porcentaje en la frontera
-- --------------------------------------------------------------------------------------------------------------------
DECLARE @casos TABLE (caso VARCHAR(40), falta DECIMAL(12,6) NULL, dictadas DECIMAL(12,6) NULL, esperado DECIMAL(5,2));
INSERT INTO @casos VALUES
    ('UNO_DEBAJO_100H',        19.990000, 100.000000, 19.99),
    ('EXACTO_100H',            20.000000, 100.000000, 20.00),
    ('UNO_ENCIMA_100H',        20.010000, 100.000000, 20.01),
    -- horas fraccionarias: 48 h dictadas, 9.6 h de falta = 20 % exacto; 9.595 h = 19.989.. -> 19.99; 9.605 h = 20.010.. -> 20.01
    ('EXACTO_FRACCION',         9.600000,  48.000000, 20.00),
    ('DEBAJO_FRACCION',         9.595000,  48.000000, 19.99),
    ('ENCIMA_FRACCION',         9.605000,  48.000000, 20.01),
    -- redondeo comercial a 2 decimales: 19.994 baja a 19.99 y 19.995 sube a 20.00 (cruza el umbral por redondeo)
    ('REDONDEO_BAJA',          19.994000, 100.000000, 19.99),
    ('REDONDEO_SUBE',          19.995000, 100.000000, 20.00),
    ('CERO_FALTA',              0.000000, 100.000000,  0.00),
    ('CERO_DICTADAS',           4.000000,   0.000000,  0.00),
    ('NULL_FALTA',                  NULL, 100.000000,  0.00),
    ('NULL_DICTADAS',           4.000000,       NULL,  0.00),
    ('NEGATIVO_FALTA',         -1.000000, 100.000000,  0.00),
    ('NEGATIVO_DICTADAS',       1.000000,  -4.000000,  0.00);
DECLARE @fallos NVARCHAR(4000) = (
    SELECT STRING_AGG(CONCAT(c.caso, '=', ISNULL(CONVERT(VARCHAR(10), dbo.ufn_calcular_porcentaje_inasistencia_horas(c.falta, c.dictadas)), 'NULL')), ', ')
    FROM @casos c
    WHERE dbo.ufn_calcular_porcentaje_inasistencia_horas(c.falta, c.dictadas) IS NULL
       OR dbo.ufn_calcular_porcentaje_inasistencia_horas(c.falta, c.dictadas) <> c.esperado);
IF @fallos IS NOT NULL
BEGIN
    DECLARE @m1 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_PRU14_01: porcentaje fuera de lo esperado: ', @fallos);
    THROW 55301, @m1, 1;
END;
PRINT 'TEST_PASS:VAL_PRU14_01_PORCENTAJE_FRONTERA';
GO

-- --------------------------------------------------------------------------------------------------------------------
-- VAL_PRU14_02: clasificacion alrededor de cada umbral (ADVERTENCIA = 15, PERDIDA = 20, fijados y revertidos)
-- --------------------------------------------------------------------------------------------------------------------
DECLARE @fallos NVARCHAR(4000);
BEGIN TRANSACTION;
BEGIN TRY
    UPDATE dbo.CatalogoParametro SET valor = N'15', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'20', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF @@ROWCOUNT <> 1 THROW 55302, 'TEST FAILED VAL_PRU14_02: no existe ASISTENCIA/UMBRAL_ALERTA_PERDIDA en CatalogoParametro.', 1;

    DECLARE @casos TABLE (caso VARCHAR(40), porcentaje DECIMAL(5,2) NULL, estado NVARCHAR(10), esperado NVARCHAR(10));
    INSERT INTO @casos VALUES
        ('CERO',                  0.00, N'A',  N'REGULAR'),
        ('ADVERTENCIA_DEBAJO',   14.99, N'A',  N'REGULAR'),
        ('ADVERTENCIA_EXACTO',   15.00, N'A',  N'RIESGO'),
        ('ADVERTENCIA_ENCIMA',   15.01, N'A',  N'RIESGO'),
        ('PERDIDA_DEBAJO',       19.99, N'A',  N'RIESGO'),
        ('PERDIDA_EXACTO',       20.00, N'A',  N'PERDIDA'),
        ('PERDIDA_ENCIMA',       20.01, N'A',  N'PERDIDA'),
        ('MAXIMO',              100.00, N'A',  N'PERDIDA'),
        -- matricula cancelada por inasistencia: PERDIDA aunque el porcentaje este debajo de cualquier umbral
        ('CI_EN_CERO',            0.00, N'CI', N'PERDIDA'),
        -- porcentaje NULL con umbrales validos: no supera ningun umbral (comparaciones con NULL son falsas)
        ('PORCENTAJE_NULL',       NULL, N'A',  N'REGULAR');
    SET @fallos = (
        SELECT STRING_AGG(CONCAT(c.caso, '=', ISNULL(dbo.ufn_clasificar_permanencia(c.porcentaje, c.estado), N'NULL')), ', ')
        FROM @casos c
        WHERE ISNULL(dbo.ufn_clasificar_permanencia(c.porcentaje, c.estado), N'NULL') <> c.esperado);
    -- Cadena completa con horas: 19.99 % de 100 h queda en RIESGO y 20.00 % pasa a PERDIDA
    IF dbo.ufn_clasificar_permanencia(dbo.ufn_calcular_porcentaje_inasistencia_horas(19.99, 100), N'A') <> N'RIESGO'
       OR dbo.ufn_clasificar_permanencia(dbo.ufn_calcular_porcentaje_inasistencia_horas(20.00, 100), N'A') <> N'PERDIDA'
       OR dbo.ufn_clasificar_permanencia(dbo.ufn_calcular_porcentaje_inasistencia_horas(20.01, 100), N'A') <> N'PERDIDA'
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'CADENA_HORAS');
    -- El umbral del motor de alertas (tipo PERDIDA) lee el mismo parametro
    IF NOT EXISTS (SELECT 1 FROM dbo.TipoAlertaInasistencia t WHERE t.claveParametroUmbral = 'UMBRAL_ALERTA_PERDIDA'
                   AND dbo.ufn_umbral_alerta_inasistencia(t.id) = 20.00)
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'UMBRAL_ALERTA_PERDIDA');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @fallos IS NOT NULL
BEGIN
    DECLARE @m2 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_PRU14_02: clasificacion fuera de lo esperado: ', @fallos);
    THROW 55303, @m2, 1;
END;
PRINT 'TEST_PASS:VAL_PRU14_02_CLASIFICACION_FRONTERA';
GO

-- --------------------------------------------------------------------------------------------------------------------
-- VAL_PRU14_03: parametro ausente, inactivo o no numerico => NULL (la regla nunca asume un umbral)
-- --------------------------------------------------------------------------------------------------------------------
DECLARE @fallos NVARCHAR(4000), @idTipoPerdida UNIQUEIDENTIFIER =
    (SELECT TOP 1 t.id FROM dbo.TipoAlertaInasistencia t WHERE t.claveParametroUmbral = 'UMBRAL_ALERTA_PERDIDA' ORDER BY t.nivel DESC);
IF @idTipoPerdida IS NULL THROW 55304, 'TEST FAILED VAL_PRU14_03: falta el tipo de alerta de PERDIDA (semilla 40_culm001_c_catalogos).', 1;
BEGIN TRANSACTION;
BEGIN TRY
    -- (a) parametro inactivo: uv_parametro no lo ve
    UPDATE dbo.CatalogoParametro SET estaActivo = 0 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_clasificar_permanencia(25.00, N'A') IS NOT NULL OR dbo.ufn_clasificar_permanencia(0.00, N'A') IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'INACTIVO_CLASIFICA');
    IF dbo.ufn_umbral_alerta_inasistencia(@idTipoPerdida) IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'INACTIVO_UMBRAL_ALERTA');
    -- (b) valor y valor por defecto vacios
    UPDATE dbo.CatalogoParametro SET estaActivo = 1, valor = N'', valorDefecto = N'' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_clasificar_permanencia(25.00, N'A') IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'VACIO_CLASIFICA');
    IF dbo.ufn_umbral_alerta_inasistencia(@idTipoPerdida) IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'VACIO_UMBRAL_ALERTA');
    -- (c) valor no numerico
    UPDATE dbo.CatalogoParametro SET valor = N'veinte', valorDefecto = N'veinte' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_clasificar_permanencia(25.00, N'A') IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'TEXTO_CLASIFICA');
    IF dbo.ufn_umbral_alerta_inasistencia(@idTipoPerdida) IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'TEXTO_UMBRAL_ALERTA');
    -- (d) fila ausente (se renombra la clave dentro de la transaccion; borrarla chocaria con las FK de edicion e historial)
    UPDATE dbo.CatalogoParametro SET clave = 'QA_PRU14_AUSENTE' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'20', valorDefecto = N'20' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_clasificar_permanencia(25.00, N'A') IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'AUSENTE_CLASIFICA');
    -- (e) valor vacio con valor por defecto valido: CatalogoParametro.valor es NOT NULL, asi que ISNULL(valor, valorDefecto) no
    --     recurre al defecto ante '' y la regla devuelve NULL en las dos funciones (comportamiento vigente: no asume un umbral)
    UPDATE dbo.CatalogoParametro SET valor = N'', valorDefecto = N'20' WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_umbral_alerta_inasistencia(@idTipoPerdida) IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'VALOR_VACIO_UMBRAL_ALERTA');
    UPDATE dbo.CatalogoParametro SET clave = 'UMBRAL_ALERTA_ADVERTENCIA' WHERE grupo = 'ASISTENCIA' AND clave = 'QA_PRU14_AUSENTE';
    IF dbo.ufn_clasificar_permanencia(25.00, N'A') IS NOT NULL
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'VALOR_VACIO_CLASIFICA');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @fallos IS NOT NULL
BEGIN
    DECLARE @m3 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_PRU14_03: con el parametro ausente o invalido la regla debe devolver NULL: ', @fallos);
    THROW 55305, @m3, 1;
END;
IF dbo.ufn_clasificar_permanencia(0.00, N'A') IS NULL
    THROW 55306, 'TEST FAILED VAL_PRU14_03: los umbrales no quedaron restablecidos despues del ROLLBACK.', 1;
PRINT 'TEST_PASS:VAL_PRU14_03_PARAMETRO_AUSENTE';
GO

-- --------------------------------------------------------------------------------------------------------------------
-- VAL_PRU14_04: maximo
-- --------------------------------------------------------------------------------------------------------------------
DECLARE @fallos NVARCHAR(4000);
IF dbo.ufn_calcular_porcentaje_inasistencia_horas(48.000000, 48.000000) <> 100.00
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'FALTA_IGUAL_DICTADAS');
IF dbo.ufn_calcular_porcentaje_inasistencia_horas(60.000000, 48.000000) <> 100.00
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'FALTA_MAYOR_ACOTA_A_100');
-- extremos del tipo DECIMAL(12,6): sin desbordamiento
IF dbo.ufn_calcular_porcentaje_inasistencia_horas(999999.999999, 999999.999999) <> 100.00
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'MAXIMO_DECIMAL');
IF dbo.ufn_calcular_porcentaje_inasistencia_horas(0.000001, 999999.999999) <> 0.00
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'MINIMO_POSITIVO');
IF dbo.ufn_calcular_porcentaje_inasistencia_horas(999999.999998, 999999.999999) <> 100.00
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'CASI_TODO_REDONDEA_A_100');
-- PERDIDA en su maximo editable (CatalogoParametroEdicion: 1..100): 99.99 queda en RIESGO y solo 100.00 es PERDIDA
BEGIN TRANSACTION;
BEGIN TRY
    UPDATE dbo.CatalogoParametro SET valor = N'15', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_ADVERTENCIA';
    UPDATE dbo.CatalogoParametro SET valor = N'100', estaActivo = 1 WHERE grupo = 'ASISTENCIA' AND clave = 'UMBRAL_ALERTA_PERDIDA';
    IF dbo.ufn_clasificar_permanencia(99.99, N'A') <> N'RIESGO'
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'PERDIDA_100_CON_99_99');
    IF dbo.ufn_clasificar_permanencia(100.00, N'A') <> N'PERDIDA'
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'PERDIDA_100_CON_100');
    IF dbo.ufn_clasificar_permanencia(dbo.ufn_calcular_porcentaje_inasistencia_horas(60, 48), N'A') <> N'PERDIDA'
        SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'PERDIDA_100_CON_FALTA_MAYOR');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
-- El rango editable del umbral de PERDIDA sigue siendo 1..100 (el maximo probado arriba es el que la edicion admite)
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
               WHERE p.grupo = 'ASISTENCIA' AND p.clave = 'UMBRAL_ALERTA_PERDIDA' AND e.valorMinimo = 1 AND e.valorMaximo = 100)
    SET @fallos = CONCAT(@fallos, IIF(@fallos IS NULL, '', ', '), 'RANGO_EDITABLE_PERDIDA');
IF @fallos IS NOT NULL
BEGIN
    DECLARE @m4 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_PRU14_04: maximo fuera de lo esperado: ', @fallos);
    THROW 55307, @m4, 1;
END;
PRINT 'TEST_PASS:VAL_PRU14_04_MAXIMO';
GO

-- --------------------------------------------------------------------------------------------------------------------
-- VAL_PRU14_05: la vista de resumen aplica la misma regla con los umbrales vigentes (ninguna fila con otra clasificacion)
-- --------------------------------------------------------------------------------------------------------------------
DECLARE @distintas INT = (
    SELECT COUNT(*)
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    WHERE r.porcentajeInasistencia <> dbo.ufn_calcular_porcentaje_inasistencia_horas(r.horasFalta, r.horasDictadas)
       OR ISNULL(r.codigoPermanencia, N'NULL') <> ISNULL(dbo.ufn_clasificar_permanencia(r.porcentajeInasistencia, r.codigoEstadoEstudiante), N'NULL'));
IF @distintas <> 0
BEGIN
    DECLARE @m5 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_PRU14_05: filas de uv_resumen_asistencia_estudiante_grupo con otra regla: ', @distintas);
    THROW 55308, @m5, 1;
END;
PRINT 'TEST_PASS:VAL_PRU14_05_VISTA_MISMA_REGLA';
GO

IF @@TRANCOUNT <> 0
    THROW 55309, 'TEST FAILED VAL_PRU14_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_PRU14_TRANCOUNT_ZERO';
GO
