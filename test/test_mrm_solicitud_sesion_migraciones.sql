-- CULM-001 / DEC-065: migracion 30 (solicitud de sesion extraordinaria con aval del coordinador; grupos solo por coordinador) up -> down -> up.
-- Lo ejecuta test/test_mrm_solicitud_sesion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/), tras bajar dentro de la transaccion las
-- migraciones posteriores (lib_componible.ps1). Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   MIG_MRM_DOWN_OK     el down quita SP, vistas, tablas, mensajes SES_022..027, plantillas, marcadores y parametro, y restaura los textos previos
--   MIG_MRM_UP1_OK      el up crea todo y deja los textos nuevos
--   MIG_MRM_UP2_OK      el up dos veces no cambia nada (mismos textos)
--   MIG_MRM_DOWN_UP_OK  down -> up deja los mismos textos que el primer up
--   MIG_MRM_ROLLBACK_OK la transaccion se revirtio
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'tempdb..#mrmmig') IS NOT NULL DROP TABLE #mrmmig;
CREATE TABLE #mrmmig (k NVARCHAR(80) PRIMARY KEY, v VARBINARY(32));
GO
:r $(MIGDIR)/30_mrm_solicitud_sesion_down.sql
GO
IF OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_validar_coordinador_sesion_interno', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_solicitud_sesion', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_estado_solicitud_sesion', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.SesionSolicitud', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.EstadoSolicitudSesion', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027'))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE'))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'SESION' AND clave = 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA')
    THROW 59950, 'TEST FAILED: MRM_MIG el down no quito los objetos de la solicitud de sesion.', 1;
IF COL_LENGTH(N'dbo.uv_sesion_estado', N'estadoSolicitud') IS NOT NULL OR COL_LENGTH(N'dbo.uv_sesion_manual', N'pendienteAprobacion') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NULL OR OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NULL
    THROW 59951, 'TEST FAILED: MRM_MIG el down debe restaurar las vistas previas y conservar los objetos de la migracion 29.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_grupo')) NOT LIKE N'%COORDINADOR,DOCENTE%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_sesion_interno')) LIKE N'%SesionSolicitud%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno')) LIKE N'%SES_023%'
    THROW 59952, 'TEST FAILED: MRM_MIG el down debe restaurar usp_crear_grupo (DOCENTE), usp_crear_sesion_interno y el validador de ventana.', 1;
PRINT 'MIG_MRM_DOWN_OK';
GO
:r $(MIGDIR)/30_mrm_solicitud_sesion_up.sql
GO
IF OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_validar_coordinador_sesion_interno', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_solicitud_sesion', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_estado_solicitud_sesion', N'V') IS NULL
   OR OBJECT_ID(N'dbo.SesionSolicitud', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EstadoSolicitudSesion', N'U') IS NULL
   OR COL_LENGTH(N'dbo.uv_sesion_estado', N'estadoSolicitud') IS NULL OR COL_LENGTH(N'dbo.uv_sesion_estado', N'pendienteAprobacion') IS NULL
   OR COL_LENGTH(N'dbo.uv_sesion_manual', N'estadoSolicitud') IS NULL OR COL_LENGTH(N'dbo.uv_sesion_manual', N'pendienteAprobacion') IS NULL
   OR (SELECT COUNT(*) FROM dbo.EstadoSolicitudSesion) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027')) <> 6
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027')) <> 6
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE activa = 1 AND tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')) <> 3
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')) <> 23
   OR dbo.ufn_obtener_parametro_texto(NULL, 'SESION', 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA') IS NULL
   OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(N'dbo.SesionSolicitud')) <> 4
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_grupo')) LIKE N'%COORDINADOR,DOCENTE%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_crear_sesion_interno')) NOT LIKE N'%SesionSolicitud%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno')) NOT LIKE N'%SES_023%'
    THROW 59953, 'TEST FAILED: MRM_MIG el up no dejo los objetos de la solicitud de sesion.', 1;
IF OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NOT NULL
   AND (SELECT COUNT(*) FROM sys.database_permissions WHERE class = 1 AND type = 'EX' AND state IN ('G', 'W')
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
          AND major_id IN (OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion'), OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion'),
                           OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado'), OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion'))) <> 4
    THROW 59954, 'TEST FAILED: MRM_MIG el up debe conceder EXECUTE de los 4 SP publicos al rol runtime.', 1;
INSERT #mrmmig SELECT o.name, HASHBYTES('SHA2_256', m.definition)
FROM sys.sql_modules m INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.schema_id = SCHEMA_ID('dbo')
  AND o.name IN (N'usp_aprobar_solicitud_sesion', N'usp_rechazar_solicitud_sesion', N'usp_consultar_solicitudes_sesion_coordinador_paginado',
                 N'usp_consultar_destinatarios_solicitud_sesion', N'usp_validar_coordinador_sesion_interno', N'uv_solicitud_sesion', N'uv_estado_solicitud_sesion',
                 N'uv_sesion_manual', N'uv_sesion_estado', N'uv_sesion_estudiante_reclamo', N'usp_validar_sesion_ventana_registro_interno',
                 N'usp_crear_sesion_interno', N'usp_crear_grupo', N'usp_consultar_destinatarios_sesion_manual', N'usp_consultar_sesiones_grupo_paginado');
IF (SELECT COUNT(*) FROM #mrmmig) <> 15 THROW 59955, 'TEST FAILED: MRM_MIG faltan objetos tras el up.', 1;
PRINT 'MIG_MRM_UP1_OK';
GO
:r $(MIGDIR)/30_mrm_solicitud_sesion_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrmmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR (SELECT COUNT(*) FROM dbo.EstadoSolicitudSesion) <> 3
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')) <> 23
   OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(N'dbo.SesionSolicitud')) <> 4
    THROW 59956, 'TEST FAILED: MRM_MIG el up repetido cambio objetos.', 1;
PRINT 'MIG_MRM_UP2_OK';
GO
:r $(MIGDIR)/30_mrm_solicitud_sesion_down.sql
GO
:r $(MIGDIR)/30_mrm_solicitud_sesion_up.sql
GO
IF EXISTS (SELECT 1 FROM #mrmmig x INNER JOIN sys.objects o ON o.name = x.k INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
           WHERE o.schema_id = SCHEMA_ID('dbo') AND x.v <> HASHBYTES('SHA2_256', m.definition))
   OR OBJECT_ID(N'dbo.SesionSolicitud', N'U') IS NULL
    THROW 59957, 'TEST FAILED: MRM_MIG down -> up no reprodujo el primer up.', 1;
PRINT 'MIG_MRM_DOWN_UP_OK';
GO
IF @@TRANCOUNT < 1 THROW 59958, 'TEST FAILED: MRM_MIG la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
PRINT 'MIG_MRM_ROLLBACK_OK';
GO
