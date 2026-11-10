-- CULM-001 / DEC-065 (5): migracion 32 (registro compuesto decano + facultad y coordinador + programa) up -> down -> up.
-- Lo ejecuta test/test_mrm_registro_compuesto.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_MRG_DOWN_OK     el down quita los dos compuestos y los dos nucleos y devuelve la logica en linea a usp_crear_decano y usp_crear_coordinador
--   MIG_MRG_UP1_OK      el up crea los cuatro SP, los publicos antiguos delegan en los nucleos y solo los compuestos tienen EXECUTE para el rol runtime
--   MIG_MRG_UP2_OK      el up dos veces no cambia nada (mismas definiciones)
--   MIG_MRG_DOWN_UP_OK  down -> up deja las mismas definiciones que el primer up
--   MIG_MRG_ROLLBACK_OK la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#mrgmig') IS NOT NULL DROP TABLE #mrgmig;
CREATE TABLE #mrgmig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/32_mrm_registro_compuesto_down.sql
GO
IF OBJECT_ID(N'dbo.usp_crear_decano_con_facultad', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_crear_decano_interno', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_interno', N'P') IS NOT NULL
    THROW 59970, 'TEST FAILED: MRG_MIG el down no quito los compuestos ni los nucleos.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_decano')) LIKE N'%usp_crear_decano_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_decano')) NOT LIKE N'%usp_sincronizar_usuario_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_coordinador')) LIKE N'%usp_crear_coordinador_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_coordinador')) NOT LIKE N'%usp_sincronizar_usuario_interno%'
    THROW 59971, 'TEST FAILED: MRG_MIG el down debe restaurar la logica en linea de usp_crear_decano y usp_crear_coordinador.', 1;
PRINT 'MIG_MRG_DOWN_OK';
GO
:r $(MIGDIR)/32_mrm_registro_compuesto_up.sql
GO
IF OBJECT_ID(N'dbo.usp_crear_decano_con_facultad', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_crear_decano_interno', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_interno', N'P') IS NULL
    THROW 59972, 'TEST FAILED: MRG_MIG el up no dejo los compuestos ni los nucleos.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_decano')) NOT LIKE N'%usp_crear_decano_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_decano')) LIKE N'%usp_sincronizar_usuario_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_coordinador')) NOT LIKE N'%usp_crear_coordinador_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_coordinador')) LIKE N'%usp_sincronizar_usuario_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_decano_con_facultad')) NOT LIKE N'%usp_crear_facultad_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa')) NOT LIKE N'%usp_insertar_programa_academico_interno%'
    THROW 59973, 'TEST FAILED: MRG_MIG el up debe hacer que los publicos antiguos deleguen en los nucleos y que los compuestos usen facultad y programa internos.', 1;
IF (SELECT COUNT(*) FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
      AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND major_id IN (OBJECT_ID(N'dbo.usp_crear_decano_con_facultad'), OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa'))) <> 2
   OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
      AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND major_id IN (OBJECT_ID(N'dbo.usp_crear_decano_interno'), OBJECT_ID(N'dbo.usp_crear_coordinador_interno')))
    THROW 59974, 'TEST FAILED: MRG_MIG el up debe conceder EXECUTE al rol runtime solo en los dos compuestos.', 1;
INSERT #mrgmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo')
  AND o.name IN (N'usp_crear_decano', N'usp_crear_coordinador', N'usp_crear_decano_interno', N'usp_crear_coordinador_interno',
                 N'usp_crear_decano_con_facultad', N'usp_crear_coordinador_con_programa');
IF (SELECT COUNT(*) FROM #mrgmig) <> 6 THROW 59975, 'TEST FAILED: MRG_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_MRG_UP1_OK';
GO
:r $(MIGDIR)/32_mrm_registro_compuesto_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrgmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
    THROW 59976, 'TEST FAILED: MRG_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_MRG_UP2_OK';
GO
:r $(MIGDIR)/32_mrm_registro_compuesto_down.sql
GO
:r $(MIGDIR)/32_mrm_registro_compuesto_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrgmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
         AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
         AND major_id IN (OBJECT_ID(N'dbo.usp_crear_decano_con_facultad'), OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa'))) <> 2
    THROW 59977, 'TEST FAILED: MRG_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_MRG_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59978, 'TEST FAILED: MRG_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_MRG_ROLLBACK_OK';
GO
