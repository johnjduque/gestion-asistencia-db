USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- INT-004 (migracion 73): usp_sincronizar_parametro_catalogo_externo copia en CatalogoParametro el valor vigente del Catalogo de
-- Parametros externo. Todo dentro de una transaccion revertida (el SP usa SAVE TRANSACTION). Parametros de prueba propios (grupo INT004).
--   INT004_01: UPSERT con valor distinto -> APLICADO, huboCambio = 1, bitacora con valor anterior y nuevo.
--   INT004_02: mismo valor -> SIN_CAMBIOS sin escritura.
--   INT004_03: mismo idEvento -> DUPLICADO sin escritura (idempotente).
--   INT004_04: evento mas antiguo que el ultimo aplicado -> OBSOLETO; uno mas reciente gana.
--   INT004_05: clave inexistente -> DESCONOCIDO, no crea filas.
--   INT004_06: valor de tipo invalido (PRM_004) y fuera de rango (PRM_005) -> RECHAZADO, estado 0, sin escritura del valor.
--   INT004_07: DELETE -> la fila se conserva y el valor vuelve a valorDefecto.
--   INT004_08: campos obligatorios, operacion invalida y correlacion ausente -> estado 0 sin resultado.
--   INT004_09: sin idEvento (reconciliacion) solo registra en bitacora los APLICADO.
--   INT004_10: grupo y clave se recortan; la clave inactiva se trata como desconocida.
PRINT 'TEST START: test_int004_sincronizar_parametro (INT-004)';

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @t0 DATETIME2(7) = SYSUTCDATETIME();
DECLARE @idNum UNIQUEIDENTIFIER = NEWID();
DECLARE @idTxt UNIQUEIDENTIFIER = NEWID();
DECLARE @idInactivo UNIQUEIDENTIFIER = NEWID();
DECLARE @filasParametro INT;

IF OBJECT_ID('tempdb..#int004Resultado') IS NOT NULL DROP TABLE #int004Resultado;
CREATE TABLE #int004Resultado (
    idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, resultado VARCHAR(20), grupo VARCHAR(100), clave VARCHAR(100), huboCambio BIT, fechaModificacion DATETIME);

BEGIN TRANSACTION;

INSERT INTO dbo.CatalogoParametro (id, grupo, clave, valor, tipoDato, valorDefecto, estaActivo)
VALUES (@idNum, 'INT004', 'NUMERICO', N'5', 'INT', N'3', 1),
       (@idTxt, 'INT004', 'TEXTO', N'uco.edu.co', 'STRING', N'defecto.edu.co', 1),
       (@idInactivo, 'INT004', 'INACTIVO', N'x', 'STRING', N'x', 0);
INSERT INTO dbo.CatalogoParametroEdicion (parametro, esEditable, valorMinimo, valorMaximo, etiqueta, descripcion, categoriaVisual, orden)
VALUES (@idNum, 1, 1, 10, N'Prueba INT004', N'Prueba INT004', N'Prueba', 0);
SELECT @filasParametro = COUNT(1) FROM dbo.CatalogoParametro;

-- INT004_01: UPSERT distinto (con espacios, que se recortan)
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = ' INT004 ', @clave = ' TEXTO ', @valor = N'  nuevo.edu.co ',
    @operacion = 'UPSERT', @idEvento = 'evt-1', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'APLICADO' AND huboCambio = 1 AND grupo = 'INT004' AND clave = 'TEXTO' AND fechaModificacion IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'nuevo.edu.co')
   OR NOT EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno WHERE idEvento = 'evt-1' AND resultado = 'APLICADO' AND valorAnterior = N'uco.edu.co' AND valorNuevo = N'nuevo.edu.co' AND parametro = @idTxt)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56460, 'TEST FAILED INT004_01: no aplico el valor nuevo.', 1;
END
PRINT 'TEST_PASS:INT004_01_APLICA_VALOR';
DELETE FROM #int004Resultado;

-- INT004_02: mismo valor
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'nuevo.edu.co',
    @operacion = 'UPSERT', @idEvento = 'evt-2', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'SIN_CAMBIOS' AND huboCambio = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno WHERE idEvento = 'evt-2' AND resultado = 'SIN_CAMBIOS')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56461, 'TEST FAILED INT004_02: el mismo valor no debe escribir.', 1;
END
PRINT 'TEST_PASS:INT004_02_MISMO_VALOR_SIN_ESCRITURA';
DELETE FROM #int004Resultado;

-- INT004_03: mismo idEvento con otro valor
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'otro.edu.co',
    @operacion = 'UPSERT', @idEvento = 'evt-1', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'DUPLICADO' AND huboCambio = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'nuevo.edu.co')
   OR (SELECT COUNT(1) FROM dbo.SincronizacionParametroExterno WHERE idEvento = 'evt-1') <> 1
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56462, 'TEST FAILED INT004_03: un evento repetido no debe aplicarse.', 1;
END
PRINT 'TEST_PASS:INT004_03_EVENTO_DUPLICADO';
DELETE FROM #int004Resultado;

-- INT004_04: evento antiguo ignorado y evento posterior aplicado
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'viejo.edu.co',
    @operacion = 'UPSERT', @idEvento = 'evt-3', @ocurridoEnUtc = '2000-01-01T00:00:00', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'OBSOLETO' AND huboCambio = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'nuevo.edu.co')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56463, 'TEST FAILED INT004_04: un evento mas antiguo no debe pisar el valor.', 1;
END
DELETE FROM #int004Resultado;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'reciente.edu.co',
    @operacion = 'UPSERT', @idEvento = 'evt-4', @ocurridoEnUtc = '2999-01-01T00:00:00', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'APLICADO' AND huboCambio = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'reciente.edu.co')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56464, 'TEST FAILED INT004_04: el evento mas reciente debe ganar.', 1;
END
PRINT 'TEST_PASS:INT004_04_ULTIMO_EVENTO_GANA';
DELETE FROM #int004Resultado;

-- INT004_05: clave inexistente
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'NO_EXISTE', @valor = N'x',
    @operacion = 'UPSERT', @idEvento = 'evt-5', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'DESCONOCIDO' AND huboCambio = 0)
   OR (SELECT COUNT(1) FROM dbo.CatalogoParametro) <> @filasParametro
   OR NOT EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno WHERE idEvento = 'evt-5' AND resultado = 'DESCONOCIDO' AND parametro IS NULL)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56465, 'TEST FAILED INT004_05: una clave inexistente no debe crear filas.', 1;
END
PRINT 'TEST_PASS:INT004_05_CLAVE_DESCONOCIDA';
DELETE FROM #int004Resultado;

-- INT004_06: tipo invalido y rango
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'NUMERICO', @valor = N'abc',
    @operacion = 'UPSERT', @idEvento = 'evt-6', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'NUMERICO', @valor = N'99',
    @operacion = 'UPSERT', @idEvento = 'evt-7', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF (SELECT COUNT(1) FROM #int004Resultado WHERE estadoResultado = 0 AND resultado = 'RECHAZADO' AND huboCambio = 0) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idNum AND valor = N'5')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56466, 'TEST FAILED INT004_06: un valor invalido no debe escribirse.', 1;
END
DELETE FROM #int004Resultado;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'NUMERICO', @valor = N'7',
    @operacion = 'UPSERT', @idEvento = 'evt-8', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'APLICADO')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idNum AND valor = N'7')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56467, 'TEST FAILED INT004_06: un valor valido dentro del rango debe aplicarse.', 1;
END
PRINT 'TEST_PASS:INT004_06_VALIDA_TIPO_Y_RANGO';
DELETE FROM #int004Resultado;

-- INT004_07: DELETE conserva la fila y vuelve al valor por defecto
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = NULL,
    @operacion = 'DELETE', @idEvento = 'evt-9', @ocurridoEnUtc = '2999-06-01T00:00:00', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'APLICADO' AND huboCambio = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'defecto.edu.co' AND estaActivo = 1)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56468, 'TEST FAILED INT004_07: DELETE debe devolver el valor por defecto y conservar la fila.', 1;
END
PRINT 'TEST_PASS:INT004_07_DELETE_VUELVE_A_DEFECTO';
DELETE FROM #int004Resultado;

-- INT004_08: campos obligatorios, operacion invalida y correlacion ausente
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = ' ', @clave = 'TEXTO', @valor = N'x', @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = ' ', @valor = N'x', @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'x', @operacion = 'BORRAR', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'  ', @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'x', @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = NULL, @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'x', @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = NULL;
IF (SELECT COUNT(1) FROM #int004Resultado WHERE estadoResultado = 0 AND resultado IS NULL AND huboCambio IS NULL) <> 6
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idTxt AND valor = N'defecto.edu.co')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56469, 'TEST FAILED INT004_08: las entradas invalidas deben rechazarse sin escribir.', 1;
END
PRINT 'TEST_PASS:INT004_08_ENTRADAS_INVALIDAS';
DELETE FROM #int004Resultado;

-- INT004_09: sin idEvento solo se registra lo aplicado
DECLARE @antesBitacora INT = (SELECT COUNT(1) FROM dbo.SincronizacionParametroExterno);
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'defecto.edu.co',
    @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = '2999-07-01T00:00:00', @idCorrelacion = @corr;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'NO_EXISTE', @valor = N'x',
    @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF (SELECT COUNT(1) FROM dbo.SincronizacionParametroExterno) <> @antesBitacora
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56470, 'TEST FAILED INT004_09: sin idEvento y sin cambio no se registra en la bitacora.', 1;
END
DELETE FROM #int004Resultado;
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'TEXTO', @valor = N'conciliado.edu.co',
    @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = '2999-08-01T00:00:00', @idCorrelacion = @corr;
IF (SELECT COUNT(1) FROM dbo.SincronizacionParametroExterno) <> @antesBitacora + 1
   OR NOT EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno WHERE idEvento IS NULL AND resultado = 'APLICADO' AND valorNuevo = N'conciliado.edu.co')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56471, 'TEST FAILED INT004_09: un valor aplicado sin idEvento si se registra.', 1;
END
PRINT 'TEST_PASS:INT004_09_RECONCILIACION_SIN_EVENTO';
DELETE FROM #int004Resultado;

-- INT004_10: clave inactiva = desconocida
INSERT INTO #int004Resultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004', @clave = 'INACTIVO', @valor = N'y',
    @operacion = 'UPSERT', @idEvento = NULL, @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004Resultado WHERE estadoResultado = 1 AND resultado = 'DESCONOCIDO')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idInactivo AND valor = N'x')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56472, 'TEST FAILED INT004_10: una clave inactiva no se sincroniza.', 1;
END
PRINT 'TEST_PASS:INT004_10_CLAVE_INACTIVA';

ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0
    THROW 56473, 'TEST FAILED INT004_TRANCOUNT_ZERO: transaccion abierta.', 1;
PRINT 'TEST_PASS:INT004_TRANCOUNT_ZERO';
GO
