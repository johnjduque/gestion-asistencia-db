-- HU018 / HU019: migracion 30 (plan de estudios y horas programadas del estudiante) up -> down -> up.
-- Lo ejecuta test/test_hu018_hu019.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de
-- UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_HU018_DOWN_OK     el down quita los dos SP y no toca los objetos existentes
--   MIG_HU018_UP1_OK      el up crea los dos SP con EXECUTE para el rol runtime
--   MIG_HU018_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_HU018_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_HU018_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#h18mig') IS NOT NULL DROP TABLE #h18mig;
CREATE TABLE #h18mig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/30_hu018_hu019_plan_horas_estudiante_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NOT NULL
    THROW 54700, 'TEST FAILED: HU018_MIG el down no quito los SP del plan y de las horas programadas.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_materias_estudiante', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_estudiante', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_asignatura_plan_estudio', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo', N'V') IS NULL
    THROW 54701, 'TEST FAILED: HU018_MIG el down no debe tocar los objetos existentes.', 1;
PRINT 'MIG_HU018_DOWN_OK';
GO
:r $(MIGDIR)/30_hu018_hu019_plan_horas_estudiante_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NULL
   OR (SELECT COUNT(*) FROM sys.database_permissions dp
       WHERE dp.major_id IN (OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante'), OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante'))
         AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
         AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')) <> 2
    THROW 54702, 'TEST FAILED: HU018_MIG el up no dejo los dos SP con EXECUTE para el rol runtime.', 1;
INSERT #h18mig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo') AND o.name IN (N'usp_consultar_plan_estudio_estudiante', N'usp_consultar_horas_programadas_estudiante');
IF (SELECT COUNT(*) FROM #h18mig) <> 2 THROW 54703, 'TEST FAILED: HU018_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_HU018_UP1_OK';
GO
:r $(MIGDIR)/30_hu018_hu019_plan_horas_estudiante_up.sql
GO
IF EXISTS (SELECT 1 FROM #h18mig x INNER JOIN sys.objects o ON o.name = x.k COLLATE DATABASE_DEFAULT INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
    THROW 54704, 'TEST FAILED: HU018_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_HU018_UP2_OK';
GO
:r $(MIGDIR)/30_hu018_hu019_plan_horas_estudiante_down.sql
GO
:r $(MIGDIR)/30_hu018_hu019_plan_horas_estudiante_up.sql
GO
IF EXISTS (SELECT 1 FROM #h18mig x INNER JOIN sys.objects o ON o.name = x.k COLLATE DATABASE_DEFAULT INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NULL
    THROW 54705, 'TEST FAILED: HU018_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_HU018_DOWN_UP_OK';
GO
IF @@TRANCOUNT <> 1 THROW 54706, 'TEST FAILED: HU018_MIG la migracion altero el nivel de transacciones.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_HU018_ROLLBACK_OK';
GO
