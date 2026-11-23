-- Regresion P3 (D2): migracion 72 up -> down -> up (rotulo RPT_ASISTENCIA_ESTADO_CANCELADA). Lo ejecuta test/test_p3_regresion_migracion_72.ps1 con sqlcmd
-- y la variable MIGDIR. Parte de una BD ya desplegada desde schema/ (con la 72). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   P3R_MIG72_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   P3R_MIG72_DOWN_OK     el down retira el mensaje (usuario y tecnico)
--   P3R_MIG72_UP2_OK      el up (dos veces) lo vuelve a sembrar una sola vez con el texto CANCELADA
--   P3R_MIG72_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA') <> 1
    THROW 59720, 'TEST FAILED: P3R_MIG72 la base inicial no tiene la 72 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/72_p3_regresion_estado_cancelada_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA' AND contenido = N'CANCELADA') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA') <> 1
    THROW 59721, 'TEST FAILED: P3R_MIG72 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'P3R_MIG72_UP1_OK';
GO
:r $(MIGDIR)/72_p3_regresion_estado_cancelada_down.sql
GO
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA')
    THROW 59722, 'TEST FAILED: P3R_MIG72 el down no retiro el mensaje.', 1;
PRINT 'P3R_MIG72_DOWN_OK';
GO
:r $(MIGDIR)/72_p3_regresion_estado_cancelada_up.sql
GO
:r $(MIGDIR)/72_p3_regresion_estado_cancelada_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA' AND contenido = N'CANCELADA') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA') <> 1
    THROW 59723, 'TEST FAILED: P3R_MIG72 el up no dejo el mensaje una sola vez.', 1;
PRINT 'P3R_MIG72_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59724, 'TEST FAILED: P3R_MIG72 transaccion abierta.', 1;
PRINT 'P3R_MIG72_ROLLBACK_OK';
GO
