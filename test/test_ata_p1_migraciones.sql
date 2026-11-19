-- ATA P1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS A, B y C): migraciones 50 y 51 up -> down -> up.
-- Lo ejecuta test/test_ata_p1_migraciones.ps1 con sqlcmd y las variables MIGDIR (copia de migrations/) y SCHEMADIR (copia de schema/).
-- Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   ATA_MIG_DOWN_OK     los down quitan los 3 SP, la tabla y los parametros del aviso, restauran el texto previo de 7 SP y 3 vistas (con TOM_012,
--                       sin cuentaParaPeriodo) y devuelven el margen a 30 por defecto (y al valor vigente si seguia en 0)
--   ATA_MIG_UP1_OK      los up crean el aviso y dejan el margen en 0 (un valor administrado distinto se respeta)
--   ATA_MIG_DOWN_UP_OK  down -> up -> schema/ deja los mismos textos que el despliegue inicial
--   ATA_MIG_UP2_OK      los up dos veces no cambian nada ni duplican semillas
--   ATA_MIG_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#atamig') IS NOT NULL DROP TABLE #atamig;
CREATE TABLE #atamig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
INSERT #atamig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo') AND o.name IN (N'usp_registrar_asistencias_toma', N'usp_consultar_tomas_sesion', N'usp_consultar_comparativa_facultades',
    N'usp_consultar_comparativa_programas_facultad', N'usp_consultar_kpis_decano', N'usp_consultar_kpis_institucion',
    N'usp_consultar_consolidado_asistencia_grupos_paginado', N'uv_resumen_asistencia_estudiante_programa_grupo', N'uv_resumen_asistencia_estudiante_grupo',
    N'uv_cumplimiento_sesion_grupo', N'usp_consultar_sesiones_pendientes_aviso_falta', N'usp_consultar_faltas_sesion_aviso', N'usp_registrar_aviso_falta_sesion');
IF (SELECT COUNT(*) FROM #atamig) <> 13 THROW 59300, 'TEST FAILED: ATA_MIG la base inicial no tiene los 13 objetos de la rama (desplegar schema/ primero).', 1;
GO
:r $(MIGDIR)/51_ata_aviso_falta_sesion_down.sql
GO
:r $(MIGDIR)/50_ata_edicion_tomas_denominador_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.AvisoFaltaSesion', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_FALTA_SESION')
    THROW 59301, 'TEST FAILED: ATA_MIG el down de la 51 no quito el aviso de falta por sesion.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_registrar_asistencias_toma') AND definition LIKE N'%TOM_012%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_cumplimiento_sesion_grupo') AND definition LIKE N'%cuentaParaPeriodo%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_resumen_asistencia_estudiante_grupo') AND definition LIKE N'%horasPeriodo%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.uv_resumen_asistencia_estudiante_programa_grupo') AND definition LIKE N'%horasPeriodo%')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_kpis_decano') AND definition LIKE N'%horasPeriodo%')
   OR NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_consultar_tomas_sesion') AND definition LIKE N'%fechaAperturaSiguienteUtc%')
    THROW 59302, 'TEST FAILED: ATA_MIG el down de la 50 no restauro el texto previo de los SP y las vistas.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS' AND (valorDefecto <> N'30' OR valor <> N'30'))
    THROW 59303, 'TEST FAILED: ATA_MIG el down de la 50 debe dejar el margen de retardo en 30 (valor y defecto).', 1;
PRINT 'ATA_MIG_DOWN_OK';
GO
:r $(MIGDIR)/50_ata_edicion_tomas_denominador_up.sql
GO
:r $(MIGDIR)/51_ata_aviso_falta_sesion_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.AvisoFaltaSesion', N'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_FALTA_SESION') <> 3
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_AvisoFaltaSesion_Sesion')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS' AND valorDefecto = N'0' AND valor = N'0')
   OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_sesiones_pendientes_aviso_falta'), (N'usp_consultar_faltas_sesion_aviso'), (N'usp_registrar_aviso_falta_sesion')) s(nombre)
              WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                                WHERE dp.major_id = OBJECT_ID(N'dbo.' + s.nombre, N'P') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
                                  AND pr.name = N'rol_asistencias_runtime'))
    THROW 59304, 'TEST FAILED: ATA_MIG los up no dejaron el aviso de falta por sesion, el margen en 0 y los permisos.', 1;
-- un valor administrado distinto de 30 se respeta
UPDATE dbo.CatalogoParametro SET valor = N'45' WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS';
GO
:r $(MIGDIR)/50_ata_edicion_tomas_denominador_up.sql
GO
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS' AND valor = N'45' AND valorDefecto = N'0')
    THROW 59305, 'TEST FAILED: ATA_MIG el up de la 50 debe respetar un valor administrado distinto de 30.', 1;
UPDATE dbo.CatalogoParametro SET valor = N'0' WHERE grupo = 'ASISTENCIA' AND clave = 'MARGEN_RETARDO_MINUTOS';
PRINT 'ATA_MIG_UP1_OK';
GO
-- Los cuerpos de la 50 llegan por deploy_schema: se re-aplican desde schema/ y se compara con la base inicial
:r $(SCHEMADIR)/views/uv_cumplimiento_sesion_grupo.sql
:r $(SCHEMADIR)/views/uv_resumen_asistencia_estudiante_grupo.sql
:r $(SCHEMADIR)/views/uv_resumen_asistencia_estudiante_programa_grupo.sql
:r $(SCHEMADIR)/stored-procedures/usp_registrar_asistencias_toma.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_tomas_sesion.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_comparativa_facultades.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_comparativa_programas_facultad.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_kpis_decano.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_kpis_institucion.sql
:r $(SCHEMADIR)/stored-procedures/usp_consultar_consolidado_asistencia_grupos_paginado.sql
GO
IF EXISTS (SELECT 1 FROM #atamig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
    THROW 59306, 'TEST FAILED: ATA_MIG down -> up -> schema/ no reprodujo los textos del despliegue inicial.', 1;
PRINT 'ATA_MIG_DOWN_UP_OK';
GO
:r $(MIGDIR)/50_ata_edicion_tomas_denominador_up.sql
GO
:r $(MIGDIR)/51_ata_aviso_falta_sesion_up.sql
GO
IF EXISTS (SELECT 1 FROM #atamig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_FALTA_SESION') <> 3
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'FALTA_ASISTENCIA_SESION_ESTUDIANTE') <> 1
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'FALTA_ASISTENCIA_SESION_ESTUDIANTE') <> 9
    THROW 59307, 'TEST FAILED: ATA_MIG el up repetido cambio objetos o duplico semillas.', 1;
PRINT 'ATA_MIG_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'ATA_MIG_ROLLBACK_OK';
GO
