-- PC puntos de control: migracion 37 up -> down -> up.
-- Lo ejecuta test/test_pc_migracion_37.ps1 con sqlcmd, MIGDIR (copia de migrations/) y CONFIRMAR_RETIRO_RECLAMO_TOMA = 1, tras bajar dentro de la
-- transaccion las migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   MIG_PC_DOWN_OK      el down quita vistas, SP, columnas, FK, indice y mensajes nuevos; restaura los textos de develop, el tope 4 y MANUAL sin marcar
--   MIG_PC_UP1_OK       el up crea todo, deja el tope en 20, MANUAL marca ausentes y concede los permisos
--   MIG_PC_UP2_OK       el up dos veces no cambia nada
--   MIG_PC_DOWN_UP_OK   down -> up deja las mismas definiciones que el primer up
--   MIG_PC_ROLLBACK_OK  la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#pcmig') IS NOT NULL DROP TABLE #pcmig;
CREATE TABLE #pcmig (k NVARCHAR(128) COLLATE DATABASE_DEFAULT PRIMARY KEY, v VARBINARY(32));
IF OBJECT_ID(N'tempdb..#pcobj') IS NOT NULL DROP TABLE #pcobj;
CREATE TABLE #pcobj (k NVARCHAR(128) COLLATE DATABASE_DEFAULT PRIMARY KEY, nuevo BIT);
INSERT #pcobj (k, nuevo) VALUES
    (N'uv_toma_punto_control', 1), (N'uv_asistencia_tramo', 1), (N'uv_asistencia_toma_estudiante', 1),
    (N'usp_consultar_resumen_tomas_sesion', 1), (N'usp_radicar_solicitud_revision_asistencia_v4', 1),
    (N'uv_asistencia_sesion_horas', 0), (N'uv_toma_asistencia', 0), (N'uv_detalle_asistencia_v2', 0), (N'uv_solicitud_revision_asistencia', 0),
    (N'usp_registrar_asistencias_toma', 0), (N'usp_consultar_tomas_sesion', 0), (N'usp_internal_radicar_solicitud_revision', 0),
    (N'usp_resolver_solicitud_revision_asistencia', 0), (N'usp_consultar_solicitudes_revision_estudiante', 0),
    (N'usp_consultar_detalle_solicitud_revision_docente', 0), (N'uv_resumen_asistencia_estudiante_grupo', 0);
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_down.sql
GO
IF EXISTS (SELECT 1 FROM #pcobj o WHERE o.nuevo = 1 AND OBJECT_ID(N'dbo.' + o.k) IS NOT NULL)
   OR EXISTS (SELECT 1 FROM #pcobj o WHERE o.nuevo = 0 AND OBJECT_ID(N'dbo.' + o.k) IS NULL)
    THROW 59900, 'TEST FAILED: PC_MIG el down debe quitar los objetos nuevos y conservar los modificados.', 1;
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NOT NULL OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'razonCausaResolucion') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name IN (N'FK_SolicitudRevisionAsistencia_TomaAsistencia', N'FK_SolicitudRevisionAsistencia_RazonCausaResolucion'))
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.SolicitudRevisionAsistencia') AND name = N'IX_SolicitudRevisionAsistencia_Asistencia_Toma')
   OR COL_LENGTH(N'dbo.uv_asistencia_sesion_horas', N'minutosSesion') IS NOT NULL OR COL_LENGTH(N'dbo.uv_toma_asistencia', N'fechaPuntoControlUtc') IS NOT NULL
   OR COL_LENGTH(N'dbo.uv_solicitud_revision_asistencia', N'idToma') IS NOT NULL
    THROW 59901, 'TEST FAILED: PC_MIG el down debe quitar las columnas, FK e indice nuevos y restaurar las vistas de develop.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_registrar_asistencias_toma')) LIKE N'%TOM[_]012%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_resolver_solicitud_revision_asistencia')) LIKE N'%codigoResultadoAprobacion%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision')) LIKE N'%@idToma%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_tomas_sesion')) LIKE N'%esEditable%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_estudiante')) LIKE N'%numeroToma%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_detalle_solicitud_revision_docente')) LIKE N'%codigoRazonCausaToma%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.uv_asistencia_sesion_horas')) LIKE N'%uv_asistencia_tramo%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.uv_resumen_asistencia_estudiante_grupo')) LIKE N'%hs.idGrupo%'
    THROW 59902, 'TEST FAILED: PC_MIG el down debe restaurar el texto de develop de cada SP y vista modificado.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029'))
   OR dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION') <> 4
   OR NOT EXISTS (SELECT 1 FROM dbo.ModoTomaAsistencia WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000001' AND marcaAusentesAlCerrar = 0)
    THROW 59903, 'TEST FAILED: PC_MIG el down debe quitar los mensajes nuevos, volver el tope a 4 y el modo MANUAL a no marcar.', 1;
PRINT 'MIG_PC_DOWN_OK';
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_up.sql
GO
IF EXISTS (SELECT 1 FROM #pcobj o WHERE OBJECT_ID(N'dbo.' + o.k) IS NULL)
   OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NULL OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'razonCausaResolucion') IS NULL
   OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE name IN (N'FK_SolicitudRevisionAsistencia_TomaAsistencia', N'FK_SolicitudRevisionAsistencia_RazonCausaResolucion')) <> 2
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.SolicitudRevisionAsistencia') AND name = N'IX_SolicitudRevisionAsistencia_Asistencia_Toma')
   OR COL_LENGTH(N'dbo.uv_asistencia_sesion_horas', N'codigoEstadoSesionEstudiante') IS NULL OR COL_LENGTH(N'dbo.uv_toma_asistencia', N'fechaAperturaSiguienteUtc') IS NULL
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_registrar_asistencias_toma')) NOT LIKE N'%TOM[_]012%'
    THROW 59904, 'TEST FAILED: PC_MIG el up debe crear los objetos, columnas, FK e indice de PC.', 1;
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029')) <> 5
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029')) <> 5
   OR dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION') <> 20
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'TOMA_ASISTENCIA' AND clave = 'MAXIMO_TOMAS_POR_SESION' AND valorDefecto = N'20')
   OR NOT EXISTS (SELECT 1 FROM dbo.ModoTomaAsistencia WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000001' AND marcaAusentesAlCerrar = 1)
    THROW 59905, 'TEST FAILED: PC_MIG el up debe sembrar los mensajes, subir el tope a 20 y hacer que MANUAL marque ausentes.', 1;
IF (SELECT COUNT(*) FROM sys.database_permissions WHERE class = 1 AND state IN ('G', 'W')
      AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND ((type = 'EX' AND major_id IN (OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v4'), OBJECT_ID(N'dbo.usp_consultar_resumen_tomas_sesion')))
        OR (type = 'SL' AND major_id = OBJECT_ID(N'dbo.uv_asistencia_toma_estudiante')))) <> 3
   OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
                AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
                AND major_id = OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision'))
    THROW 59906, 'TEST FAILED: PC_MIG el up debe conceder EXECUTE a v4 y al resumen y SELECT a uv_asistencia_toma_estudiante (no al nucleo interno).', 1;
INSERT #pcmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
INNER JOIN #pcobj x ON x.k = o.name
WHERE o.schema_id = SCHEMA_ID('dbo');
IF (SELECT COUNT(*) FROM #pcmig) <> 16 THROW 59907, 'TEST FAILED: PC_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_PC_UP1_OK';
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_up.sql
GO
IF EXISTS (SELECT 1 FROM #pcmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029')) <> 5
    THROW 59908, 'TEST FAILED: PC_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_PC_UP2_OK';
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_down.sql
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_up.sql
GO
IF EXISTS (SELECT 1 FROM #pcmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM #pcobj o WHERE OBJECT_ID(N'dbo.' + o.k) IS NOT NULL) <> 16
    THROW 59909, 'TEST FAILED: PC_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_PC_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59910, 'TEST FAILED: PC_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_PC_ROLLBACK_OK';
GO
