-- CULM-001 D.8 (CONTRACT D 9.2 D8-08): migracion 27 (KPI por horas) up -> down -> up.
-- Lo ejecuta test/test_culm001_d8.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de UNA
-- transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D8_UP1_OK        el up deja los cuatro SP por horas (columnas nuevas, ESTADO_INSCRITA, sin literal A)
--   MIG_D8_UP2_OK        el up repetido no falla ni cambia el texto
--   MIG_D8_DOWN_OK       el down deja el texto de B2 (sin columnas de horas; con el literal A)
--   MIG_D8_DOWN_UP_OK    down -> up vuelve a dejar los SP por horas
--   MIG_D8_ROLLBACK_OK   la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/27_culm001_d8_kpis_horas_up.sql
GO
IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), 0) WHERE name IN (N'horasDictadas', N'horasFalta')) <> 2
   OR (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'), 0) WHERE name IN (N'horasDictadas', N'horasFalta')) <> 2
   OR (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), 0) WHERE name IN (N'horasDictadasEstudiante', N'horasFalta')) <> 2
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado')
              AND (definition NOT LIKE N'%porcentajeSinRegistro%' OR definition LIKE N'%''A''%'))
   OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_comparativa_facultades'), (N'usp_consultar_comparativa_programas_facultad'),
                                    (N'usp_consultar_tendencia_ausentismo'), (N'usp_consultar_consolidado_asistencia_grupos_paginado')) p(nombre)
              WHERE NOT EXISTS (SELECT 1 FROM sys.sql_modules m WHERE m.object_id = OBJECT_ID(N'dbo.' + p.nombre) AND m.definition LIKE N'%ESTADO_INSCRITA%'))
    THROW 57901, 'TEST FAILED: CULM001_D8_08 el up no dejo los cuatro SP por horas.', 1;
PRINT 'MIG_D8_UP1_OK';
GO
DECLARE @hashUp VARBINARY(32) = (SELECT HASHBYTES('SHA2_256', CAST(STRING_AGG(CAST(definition AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY object_id) AS NVARCHAR(MAX)))
                                  FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'),
                                       OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado')));
EXEC sys.sp_set_session_context @key = N'd8hash', @value = @hashUp;
GO
:r $(MIGDIR)/27_culm001_d8_kpis_horas_up.sql
GO
IF SESSION_CONTEXT(N'd8hash') <> (SELECT HASHBYTES('SHA2_256', CAST(STRING_AGG(CAST(definition AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY object_id) AS NVARCHAR(MAX)))
                                  FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'),
                                       OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado')))
    THROW 57902, 'TEST FAILED: CULM001_D8_08 el up repetido cambio el texto.', 1;
PRINT 'MIG_D8_UP2_OK';
GO
:r $(MIGDIR)/27_culm001_d8_kpis_horas_down.sql
GO
IF EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), 0) WHERE name IN (N'horasDictadas', N'horasFalta'))
   OR EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'), 0) WHERE name IN (N'horasDictadas', N'horasFalta'))
   OR EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), 0) WHERE name IN (N'horasDictadasEstudiante', N'horasFalta'))
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado')
                  AND definition NOT LIKE N'%porcentajeSinRegistro%' AND definition LIKE N'%''A''%')
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo') AND definition LIKE N'%''A''%')
    THROW 57903, 'TEST FAILED: CULM001_D8_08 el down no dejo el texto de B2 (formula por sesiones, literal A).', 1;
PRINT 'MIG_D8_DOWN_OK';
GO
:r $(MIGDIR)/27_culm001_d8_kpis_horas_up.sql
GO
IF SESSION_CONTEXT(N'd8hash') <> (SELECT HASHBYTES('SHA2_256', CAST(STRING_AGG(CAST(definition AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY object_id) AS NVARCHAR(MAX)))
                                  FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades'), OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad'),
                                       OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo'), OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado')))
    THROW 57904, 'TEST FAILED: CULM001_D8_08 down -> up no restauro el texto por horas.', 1;
PRINT 'MIG_D8_DOWN_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D8_ROLLBACK_OK';
GO
