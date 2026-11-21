USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- Mensaje ERR_BD_NO_DISPONIBLE (migracion 67 y semilla 63_val_mensajes_err_pendientes):
--   ERRBD_01: existe activo en el catalogo de usuario como TECHNICAL_ERROR/ALTO con el texto institucional exacto, de 10 a 100
--             caracteres y sin marcadores, y en el catalogo tecnico con su texto exacto.
-- Solo lectura. Cada verificacion va en su propio lote.
PRINT 'TEST START: test_err_bd_no_disponible';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
               WHERE codigo = 'ERR_BD_NO_DISPONIBLE' AND estaActivo = 1
                 AND tipoMensaje = 'TECHNICAL_ERROR' AND severidad = 'ALTO')
    THROW 54951, 'TEST FAILED ERRBD_01: falta ERR_BD_NO_DISPONIBLE activo como TECHNICAL_ERROR/ALTO (migracion 67 / semilla 63).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
               WHERE codigo = 'ERR_BD_NO_DISPONIBLE'
                 AND contenido = N'El servicio no está disponible en este momento. Intenta de nuevo en unos minutos.')
    THROW 54952, 'TEST FAILED ERRBD_01: el texto de usuario de ERR_BD_NO_DISPONIBLE no es el institucional.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
           WHERE codigo = 'ERR_BD_NO_DISPONIBLE'
             AND (LEN(contenido) < 10 OR LEN(contenido) > 100 OR contenido LIKE N'%{}%'))
    THROW 54953, 'TEST FAILED ERRBD_01: el texto de ERR_BD_NO_DISPONIBLE no cumple 10-100 caracteres sin marcadores.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico
               WHERE codigo = 'ERR_BD_NO_DISPONIBLE' AND estaActivo = 1
                 AND contenido = N'La base de datos no respondió (conexión o tiempo de espera).')
    THROW 54954, 'TEST FAILED ERRBD_01: ERR_BD_NO_DISPONIBLE no tiene el mensaje tecnico activo esperado.', 1;
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_BD_NO_DISPONIBLE') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ERR_BD_NO_DISPONIBLE') <> 1
    THROW 54955, 'TEST FAILED ERRBD_01: ERR_BD_NO_DISPONIBLE debe tener exactamente una fila por catalogo.', 1;
PRINT 'TEST_PASS:ERRBD_01_MENSAJE_BD_NO_DISPONIBLE';
GO

IF @@TRANCOUNT <> 0
    THROW 54956, 'TEST FAILED ERRBD_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:ERRBD_TRANCOUNT_ZERO';
GO
