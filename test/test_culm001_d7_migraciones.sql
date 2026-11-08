-- CULM-001 D.7 (CONTRACT D §8.2 D7-03): migracion 26 (retiro del registro autonomo) up -> down -> up.
-- Lo ejecuta test/test_culm001_d7.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de UNA
-- transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D7_UP1_OK        el up deja el SP sin objeto ni permisos
--   MIG_D7_UP2_OK        el up repetido no falla ni cambia nada
--   MIG_D7_DOWN_OK       el down recrea el SP y el EXECUTE del rol runtime
--   MIG_D7_DOWN_UP_OK    down -> up vuelve a retirar el SP
--   MIG_D7_ROLLBACK_OK   la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/26_culm001_d7_retiro_registro_autonomo_up.sql
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND OBJECT_NAME(major_id) = N'usp_registrar_asistencia_estudiante_autonomo')
    THROW 57920, 'TEST FAILED: CULM001_D7_03 el up no retiro el SP autonomo.', 1;
IF OBJECT_ID(N'dbo.usp_registrar_asistencias_sesion', N'P') IS NULL
    THROW 57921, 'TEST FAILED: CULM001_D7_03 el up toco el lote.', 1;
PRINT 'MIG_D7_UP1_OK';
GO
:r $(MIGDIR)/26_culm001_d7_retiro_registro_autonomo_up.sql
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
    THROW 57922, 'TEST FAILED: CULM001_D7_03 el up repetido recreo el SP.', 1;
PRINT 'MIG_D7_UP2_OK';
GO
:r $(MIGDIR)/26_culm001_d7_retiro_registro_autonomo_down.sql
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                  WHERE dp.major_id = OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo') AND dp.permission_name = N'EXECUTE'
                    AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo')
                  AND definition LIKE N'%usp_sincronizar_asistencia_estudiante_interno%')
    THROW 57923, 'TEST FAILED: CULM001_D7_03 el down no recreo el SP con su permiso.', 1;
PRINT 'MIG_D7_DOWN_OK';
GO
:r $(MIGDIR)/26_culm001_d7_retiro_registro_autonomo_up.sql
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND OBJECT_NAME(major_id) = N'usp_registrar_asistencia_estudiante_autonomo')
    THROW 57924, 'TEST FAILED: CULM001_D7_03 down -> up no retiro el SP.', 1;
PRINT 'MIG_D7_DOWN_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D7_ROLLBACK_OK';
GO
