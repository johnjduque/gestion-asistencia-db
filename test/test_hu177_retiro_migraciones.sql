-- HU177: migracion 36 (retiro del flujo propio de recuperacion de contrasena).
-- Lo ejecuta test/test_hu177_retiro.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_RET177_LIMPIA_OK    en una BD donde se aplico la migracion 35 (simulada aqui), el up quita la tabla, los SP y las semillas
--   MIG_RET177_UP2_OK       el up repetido, o sobre una BD donde nunca se aplico la 35, no hace nada ni falla
--   MIG_RET177_DOWN_OK      el down no recrea nada
--   MIG_RET177_ROLLBACK_OK  la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
-- Simula los restos de la migracion 35 retirada: la tabla, un SP y sus semillas.
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NULL
    CREATE TABLE dbo.TokenRecuperacionClave (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, usuario UNIQUEIDENTIFIER NOT NULL, tokenHash VARBINARY(32) NOT NULL);
GO
CREATE OR ALTER PROCEDURE dbo.usp_consumir_token_recuperacion_clave AS SELECT 1 AS resto;
GO
CREATE OR ALTER PROCEDURE dbo.usp_emitir_token_recuperacion_clave AS SELECT 1 AS resto;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCL_002')
    INSERT INTO dbo.CatalogoMensajeUsuario (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES ('RCL_002', 'BUSINESS_ERROR', 'MEDIO', N'Resto de la migracion 35.', 1, SYSUTCDATETIME(), SYSUTCDATETIME());
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE' AND clave = 'TTL_MINUTOS')
    INSERT INTO dbo.CatalogoParametro (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES ('RECUPERACION_CLAVE', 'TTL_MINUTOS', N'60', 'INT', N'60', 1, SYSUTCDATETIME(), SYSUTCDATETIME());
IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE' AND marcador = 'enlace')
    INSERT INTO dbo.PlantillaNotificacionMarcador (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), 'RECUPERACION_CLAVE', 'enlace', N'Resto de la migracion 35', N'https://plataforma/x', 1);
GO
:r $(MIGDIR)/36_hu177_retiro_recuperacion_clave_up.sql
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.objects WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE N'usp[_]%[_]recuperacion[_]clave')
    THROW 59990, 'TEST FAILED: HU177_RETIRO_MIG el up no quito la tabla o los SP del flujo retirado.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'RCL[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'RCL[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE')
    THROW 59991, 'TEST FAILED: HU177_RETIRO_MIG el up no quito mensajes, parametros o plantilla del flujo retirado.', 1;
PRINT 'MIG_RET177_LIMPIA_OK';
GO
:r $(MIGDIR)/36_hu177_retiro_recuperacion_clave_up.sql
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NOT NULL
    THROW 59992, 'TEST FAILED: HU177_RETIRO_MIG el up repetido no debe recrear nada.', 1;
PRINT 'MIG_RET177_UP2_OK';
GO
:r $(MIGDIR)/36_hu177_retiro_recuperacion_clave_down.sql
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.objects WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE N'usp[_]%[_]recuperacion[_]clave')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE')
    THROW 59993, 'TEST FAILED: HU177_RETIRO_MIG el down no debe recrear el flujo retirado.', 1;
PRINT 'MIG_RET177_DOWN_OK';
GO
IF @@TRANCOUNT < 1 THROW 59994, 'TEST FAILED: HU177_RETIRO_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_RET177_ROLLBACK_OK';
GO
