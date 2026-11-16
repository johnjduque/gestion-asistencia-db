USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- REA-02 (VAL-oleada9, migracion 47 y semilla 63_val_mensajes_err_pendientes):
--   VAL_REA02_01: ERR_ALMACENAMIENTO_NO_DISPONIBLE existe activo como TECHNICAL_ERROR/ALTO, con mensaje tecnico, texto de usuario
--                 sin marcadores y de 10 a 100 caracteres (limite de MessageUcoLab).
-- Solo lectura. Cada verificacion va en su propio lote.
PRINT 'TEST START: test_val_oleada9_mensaje_almacenamiento (REA-02)';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
               WHERE codigo = 'ERR_ALMACENAMIENTO_NO_DISPONIBLE' AND estaActivo = 1
                 AND tipoMensaje = 'TECHNICAL_ERROR' AND severidad = 'ALTO')
    THROW 53995, 'TEST FAILED VAL_REA02_01: falta ERR_ALMACENAMIENTO_NO_DISPONIBLE activo como TECHNICAL_ERROR/ALTO (migracion 47 / semilla 63).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ERR_ALMACENAMIENTO_NO_DISPONIBLE' AND estaActivo = 1)
    THROW 53996, 'TEST FAILED VAL_REA02_01: ERR_ALMACENAMIENTO_NO_DISPONIBLE no tiene mensaje tecnico activo.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
           WHERE codigo = 'ERR_ALMACENAMIENTO_NO_DISPONIBLE'
             AND (LEN(contenido) < 10 OR LEN(contenido) > 100 OR contenido LIKE N'%{}%'))
    THROW 53997, 'TEST FAILED VAL_REA02_01: el texto de ERR_ALMACENAMIENTO_NO_DISPONIBLE no cumple 10-100 caracteres sin marcadores.', 1;
PRINT 'TEST_PASS:VAL_REA02_01_MENSAJE_ALMACENAMIENTO';
GO

IF @@TRANCOUNT <> 0
    THROW 54990, 'TEST FAILED VAL_REA02_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_REA02_TRANCOUNT_ZERO';
GO
