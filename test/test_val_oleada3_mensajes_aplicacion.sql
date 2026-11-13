USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- VAL-oleada3 MSG-05 (migracion 41 y semilla 62_val_mensajes_aplicacion):
--   VAL_MSG05_01: estan los 107 mensajes de usuario del backend (75 VAL_APP, 17 ACC_APP, 14 NOF_APP, 1 DIS_APP), activos y con su
--                 mensaje tecnico.
--   VAL_MSG05_02: ningun texto de usuario esta vacio y los mensajes con parametros conservan sus marcadores {}.
-- Solo lectura. Cada verificacion va en su propio lote.
PRINT 'TEST START: test_val_oleada3_mensajes_aplicacion (VAL MSG-05)';
GO

DECLARE @usuario INT = (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario
                        WHERE estaActivo = 1 AND (codigo LIKE 'VAL[_]APP[_]___' OR codigo LIKE 'ACC[_]APP[_]___'
                              OR codigo LIKE 'NOF[_]APP[_]___' OR codigo LIKE 'DIS[_]APP[_]___'));
DECLARE @porPrefijo NVARCHAR(200) = (SELECT CONCAT(
        SUM(CASE WHEN codigo LIKE 'VAL[_]APP[_]%' THEN 1 ELSE 0 END), '/',
        SUM(CASE WHEN codigo LIKE 'ACC[_]APP[_]%' THEN 1 ELSE 0 END), '/',
        SUM(CASE WHEN codigo LIKE 'NOF[_]APP[_]%' THEN 1 ELSE 0 END), '/',
        SUM(CASE WHEN codigo LIKE 'DIS[_]APP[_]%' THEN 1 ELSE 0 END))
    FROM dbo.CatalogoMensajeUsuario WHERE estaActivo = 1);
IF @usuario <> 107 OR @porPrefijo <> N'75/17/14/1'
    THROW 53960, 'TEST FAILED VAL_MSG05_01: faltan mensajes de usuario del backend (migracion 41 / semilla 62).', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario u
           WHERE (u.codigo LIKE 'VAL[_]APP[_]___' OR u.codigo LIKE 'ACC[_]APP[_]___' OR u.codigo LIKE 'NOF[_]APP[_]___'
                  OR u.codigo LIKE 'DIS[_]APP[_]___')
             AND NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico t WHERE t.codigo = u.codigo AND t.estaActivo = 1))
    THROW 53961, 'TEST FAILED VAL_MSG05_01: hay mensajes de usuario del backend sin mensaje tecnico.', 1;
PRINT 'TEST_PASS:VAL_MSG05_01_MENSAJES_SEMBRADOS';
GO

IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario
           WHERE (codigo LIKE 'VAL[_]APP[_]___' OR codigo LIKE 'ACC[_]APP[_]___' OR codigo LIKE 'NOF[_]APP[_]___'
                  OR codigo LIKE 'DIS[_]APP[_]___')
             AND LEN(LTRIM(RTRIM(contenido))) < 10)
    THROW 53962, 'TEST FAILED VAL_MSG05_02: hay un mensaje de usuario del backend vacio.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('VAL_APP_022', 1), ('VAL_APP_032', 1), ('VAL_APP_034', 1), ('VAL_APP_039', 1),
                                 ('VAL_APP_046', 1), ('VAL_APP_069', 1), ('VAL_APP_070', 2)) AS e (codigo, marcadores)
           LEFT JOIN dbo.CatalogoMensajeUsuario u ON u.codigo = e.codigo
           WHERE u.codigo IS NULL
              OR (LEN(u.contenido) - LEN(REPLACE(u.contenido, N'{}', N''))) / 2 <> e.marcadores)
    THROW 53963, 'TEST FAILED VAL_MSG05_02: un mensaje con parametros perdio sus marcadores {}.', 1;
PRINT 'TEST_PASS:VAL_MSG05_02_TEXTOS_Y_MARCADORES';
GO

IF @@TRANCOUNT <> 0
    THROW 53964, 'TEST FAILED VAL_OLEADA3_MSG_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_OLEADA3_MSG_TRANCOUNT_ZERO';
GO
