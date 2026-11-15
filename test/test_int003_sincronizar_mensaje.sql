USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- INT-003 (migracion 45): usp_sincronizar_mensaje_usuario copia en CatalogoMensajeUsuario el texto que cambio en
-- MessageUcoLab. Todo dentro de una transaccion revertida (el SP usa SAVE TRANSACTION).
--   INT003_01: texto distinto -> actualiza contenido y fechaModificacion, huboCambio = 1.
--   INT003_02: mismo texto -> exito sin escritura, huboCambio = 0 y fechaModificacion intacta.
--   INT003_03: codigo inexistente -> estado 0 (GEN_001) y no crea filas.
--   INT003_04: codigo o contenido vacios -> estado 0 y sin escritura.
--   INT003_05: sin correlacion -> estado 0.
--   INT003_06: no cambia estaActivo, tipoMensaje ni severidad.
PRINT 'TEST START: test_int003_sincronizar_mensaje (INT-003)';

DECLARE @codigo VARCHAR(100) = 'GEN_004';
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @tipo VARCHAR(50), @sev VARCHAR(20), @activo BIT, @original NVARCHAR(4000), @fecha DATETIME, @filas INT;
SELECT @tipo = tipoMensaje, @sev = severidad, @activo = estaActivo, @original = contenido
FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo;
IF @original IS NULL
    THROW 56450, 'TEST FAILED INT003: falta el mensaje GEN_004 en el seed.', 1;
SELECT @filas = COUNT(1) FROM dbo.CatalogoMensajeUsuario;

IF OBJECT_ID('tempdb..#int003Resultado') IS NOT NULL DROP TABLE #int003Resultado;
CREATE TABLE #int003Resultado (
    idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, codigo VARCHAR(100), huboCambio BIT, fechaModificacion DATETIME, existeMensaje BIT);

BEGIN TRANSACTION;

-- INT003_01: texto distinto (con espacios alrededor, que se recortan)
UPDATE dbo.CatalogoMensajeUsuario SET fechaModificacion = '2000-01-01T00:00:00' WHERE codigo = @codigo;
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = ' GEN_004 ', @contenido = N'  {} creado(a) con exito.  ', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int003Resultado WHERE estadoResultado = 1 AND huboCambio = 1 AND codigo = @codigo AND fechaModificacion > '2000-01-01' AND existeMensaje = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo AND contenido = N'{} creado(a) con exito.'
                    AND fechaModificacion > '2000-01-01')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56451, 'TEST FAILED INT003_01: no actualizo el texto del mensaje.', 1;
END
PRINT 'TEST_PASS:INT003_01_ACTUALIZA_TEXTO';
DELETE FROM #int003Resultado;

-- INT003_02: mismo texto -> sin escritura
SELECT @fecha = fechaModificacion FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo;
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = @codigo, @contenido = N'{} creado(a) con exito.', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int003Resultado WHERE estadoResultado = 1 AND huboCambio = 0 AND fechaModificacion = @fecha)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo AND fechaModificacion = @fecha)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56452, 'TEST FAILED INT003_02: el mismo texto no debe escribir.', 1;
END
PRINT 'TEST_PASS:INT003_02_MISMO_TEXTO_SIN_ESCRITURA';
DELETE FROM #int003Resultado;

-- INT003_03: codigo inexistente
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = 'INT003_NO_EXISTE', @contenido = N'Texto de prueba', @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int003Resultado WHERE estadoResultado = 0 AND codigo IS NULL AND huboCambio IS NULL AND fechaModificacion IS NULL AND existeMensaje = 0)
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'INT003_NO_EXISTE')
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario) <> @filas
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56453, 'TEST FAILED INT003_03: un codigo inexistente no debe crear filas.', 1;
END
PRINT 'TEST_PASS:INT003_03_CODIGO_INEXISTENTE';
DELETE FROM #int003Resultado;

-- INT003_04: codigo vacio y contenido vacio
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = '  ', @contenido = N'Texto', @idCorrelacion = @corr;
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = @codigo, @contenido = N'   ', @idCorrelacion = @corr;
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = NULL, @contenido = NULL, @idCorrelacion = @corr;
IF (SELECT COUNT(1) FROM #int003Resultado WHERE estadoResultado = 0 AND existeMensaje IS NULL) <> 3
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo AND contenido = N'{} creado(a) con exito.')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56454, 'TEST FAILED INT003_04: codigo o contenido vacios deben rechazarse sin escribir.', 1;
END
PRINT 'TEST_PASS:INT003_04_CAMPOS_OBLIGATORIOS';
DELETE FROM #int003Resultado;

-- INT003_05: sin correlacion
INSERT INTO #int003Resultado EXEC dbo.usp_sincronizar_mensaje_usuario @codigo = @codigo, @contenido = N'Otro texto', @idCorrelacion = NULL;
IF NOT EXISTS (SELECT 1 FROM #int003Resultado WHERE estadoResultado = 0)
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo AND contenido = N'Otro texto')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56455, 'TEST FAILED INT003_05: sin correlacion debe rechazarse.', 1;
END
PRINT 'TEST_PASS:INT003_05_CORRELACION_OBLIGATORIA';
DELETE FROM #int003Resultado;

-- INT003_06: estado, tipo y severidad intactos
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
               WHERE codigo = @codigo AND tipoMensaje = @tipo AND severidad = @sev AND estaActivo = @activo)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56456, 'TEST FAILED INT003_06: el SP no debe cambiar estado, tipo ni severidad.', 1;
END
PRINT 'TEST_PASS:INT003_06_SOLO_TEXTO';

ROLLBACK TRANSACTION;
DROP TABLE #int003Resultado;

IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @codigo AND contenido = @original)
    THROW 56457, 'TEST FAILED INT003: el texto original no se restauro tras el ROLLBACK.', 1;
GO

IF @@TRANCOUNT <> 0
    THROW 56458, 'TEST FAILED INT003_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:INT003_TRANCOUNT_ZERO';
GO
