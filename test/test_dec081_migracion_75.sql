-- DEC-081: migracion 75 up -> down -> up (preambulo comun de los SP del receso en usp_validar_ejecutor_administrador_periodo_interno). Lo ejecuta
-- test/test_dec081_migracion_75.ps1 con sqlcmd y la variable MIGDIR. Parte de una BD ya desplegada desde schema/ (con la 75). Todo ocurre dentro de UNA
-- transaccion que se revierte al final.
--   DEC081_MIG75_UP1_OK      el up sobre una BD ya desplegada deja el interno y los dos SP que lo usan (idempotente)
--   DEC081_MIG75_DOWN_OK     el down borra el interno y restaura el preambulo en linea de crear y retirar
--   DEC081_MIG75_UP2_OK      el up (dos veces) vuelve a dejar el interno y los dos SP que lo usan
--   DEC081_MIG75_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.usp_validar_ejecutor_administrador_periodo_interno', N'P') IS NULL
    THROW 59750, 'TEST FAILED: DEC081_MIG75 la base inicial no tiene la 75 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/75_dec081_dedup_preambulo_receso_up.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_ejecutor_administrador_periodo_interno', N'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_receso_academico')) NOT LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_retirar_receso_academico')) NOT LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
    THROW 59751, 'TEST FAILED: DEC081_MIG75 el up no deja el interno y los SP que lo usan.', 1;
PRINT 'DEC081_MIG75_UP1_OK';
GO
:r $(MIGDIR)/75_dec081_dedup_preambulo_receso_down.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_ejecutor_administrador_periodo_interno', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_crear_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_retirar_receso_academico', N'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_receso_academico')) LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_retirar_receso_academico')) LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_receso_academico')) NOT LIKE N'%usp_validar_id_correlacion_esta_presente_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_retirar_receso_academico')) NOT LIKE N'%usp_validar_id_correlacion_esta_presente_interno%'
    THROW 59752, 'TEST FAILED: DEC081_MIG75 el down no restauro el preambulo en linea o no borro el interno.', 1;
PRINT 'DEC081_MIG75_DOWN_OK';
GO
:r $(MIGDIR)/75_dec081_dedup_preambulo_receso_up.sql
GO
:r $(MIGDIR)/75_dec081_dedup_preambulo_receso_up.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_ejecutor_administrador_periodo_interno', N'P') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_receso_academico')) NOT LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_retirar_receso_academico')) NOT LIKE N'%usp_validar_ejecutor_administrador_periodo_interno%'
    THROW 59753, 'TEST FAILED: DEC081_MIG75 el segundo up no deja el interno y los SP que lo usan.', 1;
PRINT 'DEC081_MIG75_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59754, 'TEST FAILED: DEC081_MIG75 transaccion abierta.', 1;
PRINT 'DEC081_MIG75_ROLLBACK_OK';
GO
