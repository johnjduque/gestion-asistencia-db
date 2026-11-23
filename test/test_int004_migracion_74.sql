-- INT-004: migracion 74 up -> down -> up (CatalogoParametroEdicion.formato, CK_CPE_Formato, PRM_017, filas CIDR_LIST de RED). Lo ejecuta
-- test/test_int004_migracion_74.ps1 con sqlcmd y la variable MIGDIR. Parte de una BD ya desplegada desde schema/ (con la 74). Todo ocurre dentro
-- de UNA transaccion que se revierte al final.
--   INT004_MIG74_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   INT004_MIG74_DOWN_OK     el down retira columna, restriccion, funciones, mensaje y las filas no editables de formato
--   INT004_MIG74_UP2_OK      el up (dos veces) deja columna, restriccion, mensaje y las dos filas CIDR_LIST una sola vez
--   INT004_MIG74_ROLLBACK_OK la transaccion se revirtio y los objetos siguen desplegados
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NULL
   OR OBJECT_ID('dbo.ufn_validar_formato_valor', 'FN') IS NULL
   OR OBJECT_ID('dbo.ufn_es_cidr_valido', 'FN') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PRM_017')
    THROW 59740, 'TEST FAILED: INT004_MIG74 la base inicial no tiene la 74 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/74_int004_formato_parametros_up.sql
GO
IF (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PRM_017') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'PRM_017') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
       WHERE p.grupo = 'RED' AND p.clave IN ('CIDRS_CAMPUS', 'PROXIES_CONFIABLES') AND e.formato = 'CIDR_LIST' AND e.esEditable = 0) <> 2
    THROW 59741, 'TEST FAILED: INT004_MIG74 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'INT004_MIG74_UP1_OK';
GO
:r $(MIGDIR)/74_int004_formato_parametros_down.sql
GO
IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CPE_Formato')
   OR OBJECT_ID('dbo.ufn_validar_formato_valor', 'FN') IS NOT NULL
   OR OBJECT_ID('dbo.ufn_es_cidr_valido', 'FN') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PRM_017')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'PRM_017')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE p.grupo = 'RED')
    THROW 59742, 'TEST FAILED: INT004_MIG74 el down no retiro los objetos.', 1;
PRINT 'INT004_MIG74_DOWN_OK';
GO
:r $(MIGDIR)/74_int004_formato_parametros_up.sql
GO
:r $(MIGDIR)/74_int004_formato_parametros_up.sql
GO
IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CPE_Formato' AND parent_object_id = OBJECT_ID('dbo.CatalogoParametroEdicion'))
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PRM_017') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'PRM_017') <> 1
   OR (SELECT COUNT(1) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
       WHERE p.grupo = 'RED' AND p.clave IN ('CIDRS_CAMPUS', 'PROXIES_CONFIABLES') AND e.formato = 'CIDR_LIST' AND e.esEditable = 0) <> 2
    THROW 59743, 'TEST FAILED: INT004_MIG74 el up no dejo columna, restriccion, mensaje y filas una sola vez.', 1;
PRINT 'INT004_MIG74_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0
   OR COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NULL
   OR OBJECT_ID('dbo.ufn_validar_formato_valor', 'FN') IS NULL
    THROW 59744, 'TEST FAILED: INT004_MIG74 transaccion abierta u objetos perdidos tras el rollback.', 1;
PRINT 'INT004_MIG74_ROLLBACK_OK';
GO
