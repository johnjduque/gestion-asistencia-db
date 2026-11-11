-- HU177: migracion 35 (recuperacion de contrasena) up -> down -> up.
-- Lo ejecuta test/test_hu177.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_HU177_DOWN_OK     el down quita la tabla, los 4 SP, los mensajes, los parametros y la plantilla
--   MIG_HU177_UP1_OK      el up los crea, con EXECUTE para el rol runtime y sin permisos directos sobre la tabla
--   MIG_HU177_UP2_OK      el up dos veces no cambia nada ni duplica semillas
--   MIG_HU177_DOWN_UP_OK  down -> up deja las mismas definiciones que el primer up
--   MIG_HU177_ROLLBACK_OK la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#hu177mig') IS NOT NULL DROP TABLE #hu177mig;
CREATE TABLE #hu177mig (k NVARCHAR(128) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/35_hu177_recuperacion_clave_down.sql
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.objects WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE N'usp[_]%[_]recuperacion[_]clave')
    THROW 59980, 'TEST FAILED: HU177_MIG el down no quito la tabla o los SP.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'RCL[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'RCL[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE')
    THROW 59981, 'TEST FAILED: HU177_MIG el down no quito mensajes, parametros o plantilla.', 1;
PRINT 'MIG_HU177_DOWN_OK';
GO
:r $(MIGDIR)/35_hu177_recuperacion_clave_up.sql
GO
IF OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NULL
   OR (SELECT COUNT(*) FROM sys.objects WHERE schema_id = SCHEMA_ID('dbo') AND type = 'P' AND name LIKE N'usp[_]%[_]recuperacion[_]clave') <> 4
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenRecuperacionClave_Usuario')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenRecuperacionClave_pendiente')
    THROW 59982, 'TEST FAILED: HU177_MIG el up no creo la tabla, su FK, su indice o los 4 SP.', 1;
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003')) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('RCL_001', 'RCL_002', 'RCL_003')) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE') <> 2
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE') <> 1
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE') <> 2
    THROW 59983, 'TEST FAILED: HU177_MIG el up no sembro mensajes, parametros o plantilla.', 1;
IF (SELECT COUNT(*) FROM sys.database_permissions p INNER JOIN sys.objects o ON o.object_id = p.major_id
    WHERE p.class = 1 AND p.type = 'EX' AND p.state IN ('G', 'W') AND p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND o.name LIKE N'usp[_]%[_]recuperacion[_]clave') <> 4
   OR EXISTS (SELECT 1 FROM sys.database_permissions p WHERE p.major_id = OBJECT_ID(N'dbo.TokenRecuperacionClave')
                AND p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND p.state IN ('G', 'W'))
    THROW 59984, 'TEST FAILED: HU177_MIG permisos del rol runtime incorrectos tras el up.', 1;
INSERT #hu177mig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo') AND o.name LIKE N'usp[_]%[_]recuperacion[_]clave';
PRINT 'MIG_HU177_UP1_OK';
GO
:r $(MIGDIR)/35_hu177_recuperacion_clave_up.sql
GO
IF EXISTS (SELECT 1 FROM #hu177mig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'RCL[_]%') <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'RECUPERACION_CLAVE') <> 2
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE') <> 1
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'RECUPERACION_CLAVE') <> 2
    THROW 59985, 'TEST FAILED: HU177_MIG el up repetido cambio objetos o duplico semillas.', 1;
PRINT 'MIG_HU177_UP2_OK';
GO
:r $(MIGDIR)/35_hu177_recuperacion_clave_down.sql
GO
:r $(MIGDIR)/35_hu177_recuperacion_clave_up.sql
GO
IF (SELECT COUNT(*) FROM #hu177mig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
    WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v = HASHBYTES('SHA2_256', m.definition)) <> 4
   OR OBJECT_ID(N'dbo.TokenRecuperacionClave', N'U') IS NULL
    THROW 59986, 'TEST FAILED: HU177_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_HU177_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59987, 'TEST FAILED: HU177_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_HU177_ROLLBACK_OK';
GO
