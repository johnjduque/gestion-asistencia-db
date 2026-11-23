-- INT-004: migracion 73 up -> down -> up (bitacora SincronizacionParametroExterno, mensajes PRM_013..PRM_016, SP de sincronizacion). Lo ejecuta
-- test/test_int004_migracion_73.ps1 con sqlcmd y la variable MIGDIR. Parte de una BD ya desplegada desde schema/ (con la 73). Todo ocurre dentro
-- de UNA transaccion que se revierte al final.
--   INT004_MIG73_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   INT004_MIG73_DOWN_OK     el down retira la tabla, los dos SP y los cuatro mensajes
--   INT004_MIG73_UP2_OK      el up (dos veces) deja la tabla con sus indices y FK y los mensajes una sola vez
--   INT004_MIG73_ROLLBACK_OK la transaccion se revirtio y los objetos siguen desplegados
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID('dbo.SincronizacionParametroExterno', 'U') IS NULL
   OR OBJECT_ID('dbo.usp_sincronizar_parametro_catalogo_externo', 'P') IS NULL
   OR OBJECT_ID('dbo.usp_validar_valor_parametro_externo_interno', 'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016')) <> 4
    THROW 59730, 'TEST FAILED: INT004_MIG73 la base inicial no tiene la 73 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/73_int004_sincronizar_parametros_up.sql
GO
IF OBJECT_ID('dbo.SincronizacionParametroExterno', 'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016')) <> 4
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016')) <> 4
    THROW 59731, 'TEST FAILED: INT004_MIG73 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'INT004_MIG73_UP1_OK';
GO
:r $(MIGDIR)/73_int004_sincronizar_parametros_down.sql
GO
IF OBJECT_ID('dbo.SincronizacionParametroExterno', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.usp_sincronizar_parametro_catalogo_externo', 'P') IS NOT NULL
   OR OBJECT_ID('dbo.usp_validar_valor_parametro_externo_interno', 'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016'))
    THROW 59732, 'TEST FAILED: INT004_MIG73 el down no retiro los objetos.', 1;
PRINT 'INT004_MIG73_DOWN_OK';
GO
:r $(MIGDIR)/73_int004_sincronizar_parametros_up.sql
GO
:r $(MIGDIR)/73_int004_sincronizar_parametros_up.sql
GO
IF OBJECT_ID('dbo.SincronizacionParametroExterno', 'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SincronizacionParametroExterno') AND name = 'UX_SincronizacionParametroExterno_Evento')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SincronizacionParametroExterno') AND name = 'IX_SincronizacionParametroExterno_Parametro_Ocurrido')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SincronizacionParametroExterno_CatalogoParametro')
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016')) <> 4
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('PRM_013', 'PRM_014', 'PRM_015', 'PRM_016')) <> 4
    THROW 59733, 'TEST FAILED: INT004_MIG73 el up no dejo tabla, indices, FK y mensajes una sola vez.', 1;
PRINT 'INT004_MIG73_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0
   OR OBJECT_ID('dbo.usp_sincronizar_parametro_catalogo_externo', 'P') IS NULL
   OR OBJECT_ID('dbo.SincronizacionParametroExterno', 'U') IS NULL
    THROW 59734, 'TEST FAILED: INT004_MIG73 transaccion abierta o objetos perdidos tras el rollback.', 1;
PRINT 'INT004_MIG73_ROLLBACK_OK';
GO
