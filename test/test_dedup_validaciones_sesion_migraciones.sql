-- Migracion 34 (validaciones compartidas de sesion; sin cambio funcional) up -> down -> up.
-- Lo ejecuta test/test_dedup_validaciones_sesion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_DVS_DOWN_OK     el down quita usp_validar_docente_titular_sesion_interno y los tres SP vuelven a validar por si mismos
--   MIG_DVS_UP1_OK      el up crea el interno (sin EXECUTE para el rol runtime) y los tres SP delegan en los internos compartidos
--   MIG_DVS_UP2_OK      el up dos veces no cambia nada
--   MIG_DVS_DOWN_UP_OK  down -> up deja las mismas definiciones que el primer up
--   MIG_DVS_ROLLBACK_OK la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#dvsmig') IS NOT NULL DROP TABLE #dvsmig;
CREATE TABLE #dvsmig (k NVARCHAR(128) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/34_deduplicar_validaciones_sesion_down.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_docente_titular_sesion_interno', N'P') IS NOT NULL
    THROW 59970, 'TEST FAILED: DVS_MIG el down no quito usp_validar_docente_titular_sesion_interno.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada')) NOT LIKE N'%usp_validar_titularidad_jerarquica_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual')) NOT LIKE N'%usp_validar_titularidad_jerarquica_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador')) NOT LIKE N'%usp_validar_permiso_rbac_usuario_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador')) LIKE N'%EXEC dbo.usp_validar_coordinador_sesion_interno%'
    THROW 59971, 'TEST FAILED: DVS_MIG el down debe restaurar las validaciones propias de los tres SP.', 1;
PRINT 'MIG_DVS_DOWN_OK';
GO
:r $(MIGDIR)/34_deduplicar_validaciones_sesion_up.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_docente_titular_sesion_interno', N'P') IS NULL
    THROW 59972, 'TEST FAILED: DVS_MIG el up no creo usp_validar_docente_titular_sesion_interno.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada')) NOT LIKE N'%EXEC dbo.usp_validar_docente_titular_sesion_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual')) NOT LIKE N'%EXEC dbo.usp_validar_docente_titular_sesion_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador')) NOT LIKE N'%EXEC dbo.usp_validar_coordinador_sesion_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada')) LIKE N'%usp_validar_titularidad_jerarquica_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual')) LIKE N'%usp_validar_titularidad_jerarquica_interno%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador')) LIKE N'%usp_validar_permiso_rbac_usuario_interno%'
    THROW 59973, 'TEST FAILED: DVS_MIG el up debe dejar los tres SP delegando en los internos compartidos.', 1;
IF EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
             AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
             AND major_id = OBJECT_ID(N'dbo.usp_validar_docente_titular_sesion_interno'))
    THROW 59974, 'TEST FAILED: DVS_MIG el interno no debe tener EXECUTE para el rol runtime.', 1;
IF (SELECT COUNT(*) FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
      AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND major_id IN (OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada'), OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual'),
                       OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador'))) <> 3
    THROW 59975, 'TEST FAILED: DVS_MIG los tres SP publicos deben conservar EXECUTE para el rol runtime.', 1;
INSERT #dvsmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo')
  AND o.name IN (N'usp_validar_docente_titular_sesion_interno', N'usp_consultar_destinatarios_sesion_cancelada',
                 N'usp_consultar_destinatarios_sesion_manual', N'usp_cancelar_sesion_coordinador');
IF (SELECT COUNT(*) FROM #dvsmig) <> 4 THROW 59976, 'TEST FAILED: DVS_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_DVS_UP1_OK';
GO
:r $(MIGDIR)/34_deduplicar_validaciones_sesion_up.sql
GO
IF EXISTS (SELECT 1 FROM #dvsmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
    THROW 59977, 'TEST FAILED: DVS_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_DVS_UP2_OK';
GO
:r $(MIGDIR)/34_deduplicar_validaciones_sesion_down.sql
GO
:r $(MIGDIR)/34_deduplicar_validaciones_sesion_up.sql
GO
IF EXISTS (SELECT 1 FROM #dvsmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR OBJECT_ID(N'dbo.usp_validar_docente_titular_sesion_interno', N'P') IS NULL
    THROW 59978, 'TEST FAILED: DVS_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_DVS_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59979, 'TEST FAILED: DVS_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_DVS_ROLLBACK_OK';
GO
