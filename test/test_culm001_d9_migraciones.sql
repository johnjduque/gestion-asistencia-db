-- CULM-001 D.9-a (CONTRACT D §11.2, §14.2, D-RB-03): migracion 28 (hallazgos medios de BD) up -> down -> up.
-- Lo ejecuta test/test_culm001_d9.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Todo ocurre dentro de UNA
-- transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D9_DOWN_OK     el down quita los 3 SP nuevos y los mensajes DEC_020/NTF_020/NTF_021 y restaura los 6 SP modificados
--                      (D-RB-03: usp_consultar_sesiones_facultad_paginado vuelve al texto de B2, sin @idGrupo)
--   MIG_D9_UP1_OK      el up crea todo
--   MIG_D9_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_D9_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_D9_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#d9mig') IS NOT NULL DROP TABLE #d9mig;
CREATE TABLE #d9mig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/28_culm001_d9_hallazgos_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_periodos_academicos_paginado', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_grupo_facultad_detalle', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_validar_acceso_reporte_grupo', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021'))
    THROW 57950, 'TEST FAILED: CULM001_D9_MIG el down no quito los objetos nuevos de D.9.', 1;
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_sesiones_facultad_paginado') AND definition LIKE N'%@idGrupo%')
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_sesiones_facultad_paginado') AND definition LIKE N'%CULM-001 B2NM (R5)%')
    THROW 57951, 'TEST FAILED: CULM001_D9_MIG (D-RB-03) el down no dejo el texto de B2 de usp_consultar_sesiones_facultad_paginado.', 1;
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano') AND definition LIKE N'%DEC_020%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_reintentar_notificacion_saliente_interno') AND definition LIKE N'%NTF_020%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_plantilla_notificacion_activa') AND definition LIKE N'%validarExistencia%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_periodo_academico') AND definition LIKE N'%idPeriodo               = IIF%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_validar_cruce_horario_estudiante_interno') AND definition LIKE N'%ESTADO_INSCRITA%')
    THROW 57952, 'TEST FAILED: CULM001_D9_MIG el down no restauro algun SP modificado.', 1;
PRINT 'MIG_D9_DOWN_OK';
GO
:r $(MIGDIR)/28_culm001_d9_hallazgos_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_periodos_academicos_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_grupo_facultad_detalle', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_validar_acceso_reporte_grupo', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021')) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021')) <> 3
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano') AND definition LIKE N'%DEC_020%')
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_sesiones_facultad_paginado') AND definition LIKE N'%@idGrupo%')
    THROW 57953, 'TEST FAILED: CULM001_D9_MIG el up no dejo los objetos de D.9.', 1;
INSERT #d9mig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN (N'usp_crear_decano', N'usp_reintentar_notificacion_saliente_interno', N'usp_consultar_plantilla_notificacion_activa', N'usp_crear_periodo_academico',
                 N'usp_consultar_sesiones_facultad_paginado', N'usp_validar_cruce_horario_estudiante_interno', N'usp_consultar_periodos_academicos_paginado',
                 N'usp_consultar_grupo_facultad_detalle', N'usp_validar_acceso_reporte_grupo');
IF (SELECT COUNT(*) FROM #d9mig) <> 9 THROW 57954, 'TEST FAILED: CULM001_D9_MIG faltan SP tras el up.', 1;
PRINT 'MIG_D9_UP1_OK';
GO
:r $(MIGDIR)/28_culm001_d9_hallazgos_up.sql
GO
IF EXISTS (SELECT 1 FROM #d9mig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021')) <> 3
    THROW 57955, 'TEST FAILED: CULM001_D9_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_D9_UP2_OK';
GO
:r $(MIGDIR)/28_culm001_d9_hallazgos_down.sql
GO
:r $(MIGDIR)/28_culm001_d9_hallazgos_up.sql
GO
IF EXISTS (SELECT 1 FROM #d9mig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
    THROW 57956, 'TEST FAILED: CULM001_D9_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_D9_DOWN_UP_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D9_ROLLBACK_OK';
GO
