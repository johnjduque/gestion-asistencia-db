-- HU074: migracion 57 up -> down -> up.
-- Lo ejecuta test/test_hu074_migracion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Parte de una BD ya desplegada
-- desde schema/ (con la 57). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   HU074_MIG_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   HU074_MIG_DOWN_OK     el down quita el interno y los mensajes ASI_009..ASI_012 y el toggle vuelve a GEN_004 (sin ASI_009 ni
--                         @estaActivaDeseada)
--   HU074_MIG_UP2_OK      el up (dos veces) recrea el interno, los mensajes, las reglas en los tres SP, @estaActivaDeseada y el
--                         bloqueo de fila del toggle y de usp_crear_grupo
--   HU074_MIG_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.usp_validar_asignatura_activa_interno', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ASI_009', 'ASI_010', 'ASI_011', 'ASI_012')) <> 4
    THROW 59570, 'TEST FAILED: HU074_MIG la base inicial no tiene la 57 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/57_hu074_estado_asignatura_reglas_up.sql
GO
PRINT 'HU074_MIG_UP1_OK';
GO
:r $(MIGDIR)/57_hu074_estado_asignatura_reglas_down.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_asignatura_activa_interno', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ASI_009', 'ASI_010', 'ASI_011', 'ASI_012'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('ASI_009', 'ASI_010', 'ASI_011', 'ASI_012'))
   OR CHARINDEX(N'ASI_009', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_toggle_estado_asignatura'))) > 0
   OR EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_toggle_estado_asignatura') AND name = N'@estaActivaDeseada')
   OR CHARINDEX(N'GEN_004', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_toggle_estado_asignatura'))) = 0
   OR CHARINDEX(N'usp_validar_asignatura_activa_interno', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_grupo'))) > 0
   OR CHARINDEX(N'usp_validar_asignatura_activa_interno', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_asociar_asignatura_plan'))) > 0
    THROW 59571, 'TEST FAILED: HU074_MIG el down no restauro los SP ni retiro el interno y los mensajes.', 1;
PRINT 'HU074_MIG_DOWN_OK';
GO
:r $(MIGDIR)/57_hu074_estado_asignatura_reglas_up.sql
GO
:r $(MIGDIR)/57_hu074_estado_asignatura_reglas_up.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_asignatura_activa_interno', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ASI_009', 'ASI_010', 'ASI_011', 'ASI_012')) <> 4
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('ASI_009', 'ASI_010', 'ASI_011', 'ASI_012')) <> 4
   OR CHARINDEX(N'ASI_009', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_toggle_estado_asignatura'))) = 0
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_toggle_estado_asignatura') AND name = N'@estaActivaDeseada')
   OR CHARINDEX(N'UPDLOCK', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_toggle_estado_asignatura'))) = 0
   OR CHARINDEX(N'@bloquearFila = 1', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_grupo'))) = 0
   OR CHARINDEX(N'usp_validar_asignatura_activa_interno', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_grupo'))) = 0
   OR CHARINDEX(N'usp_validar_asignatura_activa_interno', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_asociar_asignatura_plan'))) = 0
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                  WHERE dp.major_id = OBJECT_ID(N'dbo.usp_toggle_estado_asignatura') AND dp.permission_name = N'EXECUTE'
                    AND dp.state_desc = N'GRANT' AND pr.name = N'rol_asistencias_runtime')
    THROW 59572, 'TEST FAILED: HU074_MIG el up no recreo el interno, los mensajes, las reglas o el EXECUTE del toggle.', 1;
PRINT 'HU074_MIG_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59573, 'TEST FAILED: HU074_MIG quedo una transaccion abierta.', 1;
PRINT 'HU074_MIG_ROLLBACK_OK';
GO
