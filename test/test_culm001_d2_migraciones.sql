-- CULM-001 D.2 (CONTRACT §3.2 D2-13): migracion 21 (soportes multiples y categoria) up -> down (con confirmacion) -> up.
-- Lo ejecuta test/test_culm001_d2.ps1 con sqlcmd y las variables MIGDIR (copia de migrations/ y test/) y
-- CONFIRMAR_COLAPSO_SOPORTES=1. Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_D2_UP0_OK          el up (idempotente) deja los objetos de D.2 y el fixture radica 2 solicitudes (MED con 2 soportes, CAL con 1)
--   MIG_D2_DOWN_OK         el down con confirmacion: UX unico filtrado de vuelta, sin columna de categoria ni requiereSoporte,
--                          v2/R2/detalle/lista/autorizado en el texto de D.1, sin v3/interno/configuracion/uv_soporte_reclamo, categorias y soporte
--                          colapsado archivados en zz_archivo_*, la solicitud con 2 soportes queda con 1 ATTACHED y 1 ORPHAN
--   MIG_D2_UP1_OK          el up siguiente RESTAURA las categorias y el vinculo colapsado desde el archivo (no borra las tablas zz_archivo_*)
--   MIG_D2_UP2_OK          el up repetido no cambia ningun texto
--   MIG_D2_DOWN_UP_OK      down -> up reproduce los mismos textos
--   MIG_D2_ROLLBACK_OK     la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_up.sql
GO
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NULL
   OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'categoriaJustificacion') IS NULL
   OR COL_LENGTH(N'dbo.CategoriaJustificacion', N'requiereSoporte') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ArchivoSoporte') AND name = N'IX_ArchivoSoporte_Solicitud' AND is_unique = 0 AND has_filter = 0)
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ArchivoSoporte') AND name = N'UX_ArchivoSoporte_Solicitud')
   OR (SELECT COUNT(*) FROM dbo.CategoriaJustificacion WHERE requiereSoporte = 1 AND codigo IN (N'MED', N'ACA', N'LAB')) <> 3
    THROW 57900, 'TEST FAILED: CULM001_D2_13 el up no dejo los objetos de D.2.', 1;
PRINT 'MIG_D2_UP0_OK';
GO
:r $(MIGDIR)/fixtures/culm001_d2_fixture.sql
GO
IF OBJECT_ID(N'tempdb..#d2mig') IS NOT NULL DROP TABLE #d2mig;
CREATE TABLE #d2mig (k NVARCHAR(60) PRIMARY KEY, v VARBINARY(32));
INSERT #d2mig
SELECT CONCAT(N'up_', o.name), HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN (N'usp_radicar_solicitud_revision_asistencia_v2', N'usp_radicar_solicitud_revision_asistencia_v3', N'usp_internal_radicar_solicitud_revision',
                 N'usp_consultar_solicitudes_revision_docente', N'usp_consultar_detalle_solicitud_revision_docente', N'usp_consultar_solicitudes_revision_estudiante',
                 N'usp_consultar_archivo_soporte_autorizado', N'usp_consultar_configuracion_reclamos', N'uv_soporte_reclamo', N'uv_categoria_justificacion',
                 N'uv_solicitud_revision_asistencia');
IF (SELECT COUNT(*) FROM #d2mig) <> 11 THROW 57901, 'TEST FAILED: CULM001_D2_13 faltan objetos tras el up.', 1;
GO
:setvar CONFIRMAR_COLAPSO_SOPORTES 1
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_down.sql
GO
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NOT NULL
   OR COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'categoriaJustificacion') IS NOT NULL
   OR COL_LENGTH(N'dbo.CategoriaJustificacion', N'requiereSoporte') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ArchivoSoporte') AND name = N'IX_ArchivoSoporte_Solicitud')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ArchivoSoporte') AND name = N'UX_ArchivoSoporte_Solicitud' AND is_unique = 1 AND has_filter = 1)
   OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SolicitudRevisionAsistencia_CategoriaJustificacion')
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2')
              AND (definition LIKE N'%usp_internal_radicar_solicitud_revision%' OR definition NOT LIKE N'%usp_internal_validar_plazo_justificacion%'))
   OR EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id IN (OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), OBJECT_ID(N'dbo.usp_consultar_detalle_solicitud_revision_docente'),
              OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_estudiante')) AND definition LIKE N'%codigoCategoria%')
    THROW 57902, 'TEST FAILED: CULM001_D2_13 el down no restauro el estado anterior a D.2.', 1;
IF OBJECT_ID(N'dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2', N'U') IS NULL OR OBJECT_ID(N'dbo.zz_archivo_SoporteColapsado_culm001_d2', N'U') IS NULL
    THROW 57903, 'TEST FAILED: CULM001_D2_13 el down no archivo categorias y soportes colapsados.', 1;
IF (SELECT COUNT(*) FROM dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 z INNER JOIN #d2fx f ON f.v = z.id AND f.k IN (N'sol1', N'sol2')) <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 z INNER JOIN #d2fx s ON s.k = N'sol1' AND s.v = z.id INNER JOIN #d2fx c ON c.k = N'med' AND c.v = z.categoriaJustificacion)
   OR NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 z INNER JOIN #d2fx s ON s.k = N'sol2' AND s.v = z.id INNER JOIN #d2fx c ON c.k = N'cal' AND c.v = z.categoriaJustificacion)
    THROW 57904, 'TEST FAILED: CULM001_D2_13 las categorias guardadas no se archivaron.', 1;
IF (SELECT COUNT(*) FROM dbo.zz_archivo_SoporteColapsado_culm001_d2 z INNER JOIN #d2fx s ON s.k = N'sol1' AND s.v = z.idSolicitud) <> 1
   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN #d2fx s ON s.k = N'sol1' AND s.v = a.solicitudRevisionAsistencia WHERE a.estado = 'ATTACHED') <> 1
   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN dbo.zz_archivo_SoporteColapsado_culm001_d2 z ON z.idArchivo = a.id
       WHERE a.estado = 'ORPHAN' AND a.solicitudRevisionAsistencia IS NULL AND a.fechaAdjuncionUtc IS NULL AND a.idCorrelacionAdjuncion IS NULL) <> 1
   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN #d2fx s ON s.k = N'sol2' AND s.v = a.solicitudRevisionAsistencia WHERE a.estado = 'ATTACHED') <> 1
    THROW 57905, 'TEST FAILED: CULM001_D2_13 el colapso no dejo 1 ATTACHED + 1 ORPHAN archivado.', 1;
PRINT 'MIG_D2_DOWN_OK';
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia r INNER JOIN #d2fx f ON f.v = r.id AND f.k = N'sol1' INNER JOIN #d2fx c ON c.k = N'med' AND c.v = r.categoriaJustificacion) <> 1
   OR (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia r INNER JOIN #d2fx f ON f.v = r.id AND f.k = N'sol2' INNER JOIN #d2fx c ON c.k = N'cal' AND c.v = r.categoriaJustificacion) <> 1
   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN #d2fx s ON s.k = N'sol1' AND s.v = a.solicitudRevisionAsistencia WHERE a.estado = 'ATTACHED') <> 2
   OR OBJECT_ID(N'dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2', N'U') IS NULL OR OBJECT_ID(N'dbo.zz_archivo_SoporteColapsado_culm001_d2', N'U') IS NULL
    THROW 57906, 'TEST FAILED: CULM001_D2_13 el up no restauro las categorias y los vinculos desde el archivo.', 1;
PRINT 'MIG_D2_UP1_OK';
GO
INSERT #d2mig
SELECT CONCAT(N'up1_', o.name), HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN (N'usp_radicar_solicitud_revision_asistencia_v2', N'usp_radicar_solicitud_revision_asistencia_v3', N'usp_internal_radicar_solicitud_revision',
                 N'usp_consultar_solicitudes_revision_docente', N'usp_consultar_detalle_solicitud_revision_docente', N'usp_consultar_solicitudes_revision_estudiante',
                 N'usp_consultar_archivo_soporte_autorizado', N'usp_consultar_configuracion_reclamos', N'uv_soporte_reclamo', N'uv_categoria_justificacion',
                 N'uv_solicitud_revision_asistencia');
IF EXISTS (SELECT 1 FROM #d2mig a INNER JOIN #d2mig b ON b.k = REPLACE(a.k, N'up_', N'up1_') AND b.v <> a.v WHERE a.k LIKE N'up[_]%')
   OR (SELECT COUNT(*) FROM #d2mig WHERE k LIKE N'up1[_]%') <> 11
    THROW 57907, 'TEST FAILED: CULM001_D2_13 down -> up no reprodujo los textos del primer up.', 1;
PRINT 'MIG_D2_DOWN_UP_OK';
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_up.sql
GO
IF EXISTS (SELECT 1 FROM #d2mig a
           INNER JOIN (SELECT CONCAT(N'up_', o.name) k, HASHBYTES('SHA2_256', m.definition) v FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
                       WHERE o.name IN (N'usp_radicar_solicitud_revision_asistencia_v2', N'usp_radicar_solicitud_revision_asistencia_v3', N'usp_internal_radicar_solicitud_revision',
                                        N'usp_consultar_solicitudes_revision_docente', N'usp_consultar_detalle_solicitud_revision_docente', N'usp_consultar_solicitudes_revision_estudiante',
                                        N'usp_consultar_archivo_soporte_autorizado', N'usp_consultar_configuracion_reclamos', N'uv_soporte_reclamo', N'uv_categoria_justificacion',
                                        N'uv_solicitud_revision_asistencia')) n ON n.k = a.k AND n.v <> a.v
           WHERE a.k LIKE N'up[_]%')
    THROW 57908, 'TEST FAILED: CULM001_D2_13 el up repetido cambio objetos.', 1;
PRINT 'MIG_D2_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D2_ROLLBACK_OK';
GO
