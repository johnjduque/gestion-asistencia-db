-- CULM-001 / DEC-065 (1): migracion 31 (la cancelacion por inasistencia la decide el coordinador; consulta de revisiones del docente) up -> down -> up.
-- Lo ejecuta test/test_mrm_coordinador_cancelacion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_MRC_DOWN_OK     el down quita el SP del docente y RCN_016 y restaura el escalamiento al decano y los textos previos de RCN_013 y RCN_015
--   MIG_MRC_UP1_OK      el up crea el SP del docente (con EXECUTE para el rol runtime), retira la CTE de decanos y deja los textos nuevos
--   MIG_MRC_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_MRC_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_MRC_ROLLBACK_OK la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#mrcmig') IS NOT NULL DROP TABLE #mrcmig;
CREATE TABLE #mrcmig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/31_mrm_coordinador_decide_cancelacion_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_docente_paginado', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCN_016')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RCN_016')
    THROW 59960, 'TEST FAILED: MRC_MIG el down no quito el SP del docente ni RCN_016.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_revision_cancelacion_resolutores')) NOT LIKE N'%decanos AS%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_decidir_revision_cancelacion')) NOT LIKE N'%ESCALAR%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_actualizar_resolutores_revisiones_cancelacion')) NOT LIKE N'%ESCALAR%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_resolver_revision_cancelacion')) LIKE N'%RCN_016%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_decano_paginado')) NOT LIKE N'%codigoPerfilResolutorActual = N''DECANO''%'
    THROW 59961, 'TEST FAILED: MRC_MIG el down debe restaurar el escalamiento al decano en la funcion y los cuatro SP.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCN_013' AND contenido LIKE N'%ni un decano activo%')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCN_015' AND contenido LIKE N'%se envió a la decanatura%')
    THROW 59962, 'TEST FAILED: MRC_MIG el down debe restaurar los textos previos de RCN_013 y RCN_015.', 1;
PRINT 'MIG_MRC_DOWN_OK';
GO
:r $(MIGDIR)/31_mrm_coordinador_decide_cancelacion_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_docente_paginado', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('RCN_013', 'RCN_015', 'RCN_016')) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('RCN_013', 'RCN_015', 'RCN_016')) <> 3
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCN_013' AND contenido LIKE N'%solicite su asignación al decano%')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RCN_016' AND contenido LIKE N'%corresponde al coordinador del programa%')
    THROW 59963, 'TEST FAILED: MRC_MIG el up no dejo el SP del docente ni los mensajes RCN_013/015/016.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_revision_cancelacion_resolutores')) LIKE N'%decanos AS%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_decidir_revision_cancelacion')) LIKE N'%ESCALAR%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_actualizar_resolutores_revisiones_cancelacion')) LIKE N'%N''ESCALAR''%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_resolver_revision_cancelacion')) NOT LIKE N'%RCN_016%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_resolver_revision_cancelacion')) LIKE N'%/api/v1/decano/%'
    THROW 59964, 'TEST FAILED: MRC_MIG el up debe retirar el escalamiento al decano de la funcion y los SP.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
                 AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
                 AND major_id = OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_docente_paginado'))
    THROW 59965, 'TEST FAILED: MRC_MIG el up debe conceder EXECUTE del SP del docente al rol runtime.', 1;
INSERT #mrcmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo')
  AND o.name IN (N'ufn_revision_cancelacion_resolutores', N'usp_decidir_revision_cancelacion', N'usp_actualizar_resolutores_revisiones_cancelacion',
                 N'usp_resolver_revision_cancelacion', N'usp_consultar_revisiones_cancelacion_decano_paginado', N'usp_consultar_revisiones_cancelacion_docente_paginado');
IF (SELECT COUNT(*) FROM #mrcmig) <> 6 THROW 59966, 'TEST FAILED: MRC_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_MRC_UP1_OK';
GO
:r $(MIGDIR)/31_mrm_coordinador_decide_cancelacion_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrcmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('RCN_013', 'RCN_015', 'RCN_016')) <> 3
    THROW 59967, 'TEST FAILED: MRC_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_MRC_UP2_OK';
GO
:r $(MIGDIR)/31_mrm_coordinador_decide_cancelacion_down.sql
GO
:r $(MIGDIR)/31_mrm_coordinador_decide_cancelacion_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrcmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_docente_paginado', N'P') IS NULL
    THROW 59968, 'TEST FAILED: MRC_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_MRC_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59969, 'TEST FAILED: MRC_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_MRC_ROLLBACK_OK';
GO
