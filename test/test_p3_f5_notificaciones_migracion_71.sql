-- P3 fase F5: migracion 71 up -> down -> up (plantillas y cola administrativa al Servicio de Notificaciones).
-- Lo ejecuta test/test_p3_f5_notificaciones_migracion_71.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Parte de una BD ya desplegada
-- desde schema/ (con la 71). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   P3F5_MIG71_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente); los objetos retirados no existen y los conservados si
--   P3F5_MIG71_DOWN_OK     el down recrea las 2 tablas (22 plantillas y 124 marcadores de fabrica), la vista y los 12 SP con sus GRANT, restituye NTF_006/007/009 y quita los 22 mensajes nuevos
--   P3F5_MIG71_UP2_OK      el up (dos veces) vuelve a retirar todo y deja los mensajes nuevos (usuario y tecnico)
--   P3F5_MIG71_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE name IN (N'PlantillaNotificacion', N'PlantillaNotificacionMarcador', N'uv_notificacion_saliente_admin',
        N'usp_consultar_plantillas_notificacion_admin', N'usp_consultar_plantillas_notificacion_admin_interno', N'usp_guardar_plantilla_notificacion', N'usp_guardar_plantilla_notificacion_interno',
        N'usp_activar_version_plantilla_notificacion', N'usp_activar_version_plantilla_notificacion_interno', N'usp_consultar_plantilla_notificacion_activa', N'usp_consultar_plantilla_notificacion_activa_interno',
        N'usp_consultar_notificaciones_salientes_admin', N'usp_consultar_notificaciones_salientes_admin_interno', N'usp_reintentar_notificacion_saliente', N'usp_reintentar_notificacion_saliente_interno'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009'))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA')) <> 22
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA')) <> 22
    THROW 59710, 'TEST FAILED: P3F5_MIG71 la base inicial no tiene la 71 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/71_p3_f5_notificaciones_servicio_up.sql
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE name IN (N'PlantillaNotificacion', N'PlantillaNotificacionMarcador', N'uv_notificacion_saliente_admin',
        N'usp_consultar_plantillas_notificacion_admin', N'usp_consultar_plantillas_notificacion_admin_interno', N'usp_guardar_plantilla_notificacion', N'usp_guardar_plantilla_notificacion_interno',
        N'usp_activar_version_plantilla_notificacion', N'usp_activar_version_plantilla_notificacion_interno', N'usp_consultar_plantilla_notificacion_activa', N'usp_consultar_plantilla_notificacion_activa_interno',
        N'usp_consultar_notificaciones_salientes_admin', N'usp_consultar_notificaciones_salientes_admin_interno', N'usp_reintentar_notificacion_saliente', N'usp_reintentar_notificacion_saliente_interno'))
   OR (SELECT COUNT(*) FROM sys.objects WHERE name IN (N'NotificacionSaliente', N'EstadoNotificacion', N'TokenVerificacionCorreo', N'usp_registrar_notificacion_saliente',
        N'usp_reservar_notificaciones_salientes', N'usp_marcar_notificacion_entregada', N'usp_registrar_fallo_notificacion', N'usp_depurar_notificaciones_salientes', N'usp_consultar_contacto_notificacion')) <> 9
   OR DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_contacto_notificacion') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA')) <> 22
    THROW 59711, 'TEST FAILED: P3F5_MIG71 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'P3F5_MIG71_UP1_OK';
GO
:r $(MIGDIR)/71_p3_f5_notificaciones_servicio_down.sql
GO
IF OBJECT_ID(N'dbo.PlantillaNotificacion', N'U') IS NULL OR OBJECT_ID(N'dbo.PlantillaNotificacionMarcador', N'U') IS NULL
   OR OBJECT_ID(N'dbo.uv_notificacion_saliente_admin', N'V') IS NULL
   OR (SELECT COUNT(*) FROM sys.objects WHERE type = 'P' AND name IN (
        N'usp_consultar_plantillas_notificacion_admin', N'usp_consultar_plantillas_notificacion_admin_interno', N'usp_guardar_plantilla_notificacion', N'usp_guardar_plantilla_notificacion_interno',
        N'usp_activar_version_plantilla_notificacion', N'usp_activar_version_plantilla_notificacion_interno', N'usp_consultar_plantilla_notificacion_activa', N'usp_consultar_plantilla_notificacion_activa_interno',
        N'usp_consultar_notificaciones_salientes_admin', N'usp_consultar_notificaciones_salientes_admin_interno', N'usp_reintentar_notificacion_saliente', N'usp_reintentar_notificacion_saliente_interno')) <> 12
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion) <> 22
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE version = 1 AND activa = 1 AND creadoPor IS NULL) <> 22
   OR (SELECT COUNT(DISTINCT tipo) FROM dbo.PlantillaNotificacion) <> 22
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador) <> 124
   OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'ALERTA_PERDIDA_INASISTENCIA' AND cuerpo LIKE N'%{limite}%')
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'RECUPERACION_CLAVE')
   OR (SELECT COUNT(*) FROM sys.database_permissions dp INNER JOIN sys.objects o ON o.object_id = dp.major_id
       WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND dp.state IN ('G', 'W') AND dp.permission_name IN (N'EXECUTE', N'SELECT')
         AND o.name IN (N'usp_consultar_plantillas_notificacion_admin', N'usp_guardar_plantilla_notificacion', N'usp_activar_version_plantilla_notificacion', N'usp_consultar_plantilla_notificacion_activa',
                        N'usp_consultar_notificaciones_salientes_admin', N'usp_reintentar_notificacion_saliente', N'uv_notificacion_saliente_admin')) <> 7
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009')) <> 3
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009')) <> 3
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA'))
    THROW 59712, 'TEST FAILED: P3F5_MIG71 el down no recreo las tablas, la semilla, los SP, los permisos o los mensajes.', 1;
PRINT 'P3F5_MIG71_DOWN_OK';
GO
:r $(MIGDIR)/71_p3_f5_notificaciones_servicio_up.sql
GO
:r $(MIGDIR)/71_p3_f5_notificaciones_servicio_up.sql
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE name IN (N'PlantillaNotificacion', N'PlantillaNotificacionMarcador', N'uv_notificacion_saliente_admin',
        N'usp_consultar_plantillas_notificacion_admin', N'usp_consultar_plantillas_notificacion_admin_interno', N'usp_guardar_plantilla_notificacion', N'usp_guardar_plantilla_notificacion_interno',
        N'usp_activar_version_plantilla_notificacion', N'usp_activar_version_plantilla_notificacion_interno', N'usp_consultar_plantilla_notificacion_activa', N'usp_consultar_plantilla_notificacion_activa_interno',
        N'usp_consultar_notificaciones_salientes_admin', N'usp_consultar_notificaciones_salientes_admin_interno', N'usp_reintentar_notificacion_saliente', N'usp_reintentar_notificacion_saliente_interno'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009'))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA')) <> 22
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' OR codigo LIKE 'OK[_]%' OR (codigo LIKE 'RPT[_]ASISTENCIA[_]%' AND codigo <> 'RPT_ASISTENCIA_ESTADO_CANCELADA')) <> 22
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_NOTIFICACIONES_NO_DISPONIBLE' AND contenido = N'El servicio de notificaciones no está disponible en este momento. Intenta de nuevo en unos minutos.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_ASISTIO' AND contenido = N'ASISTIÓ')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'OK_REALTIME_001' AND contenido = N'Evento reactivo emitido a {0} suscriptores.')
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('NTF_004', 'NTF_008')) <> 2
    THROW 59713, 'TEST FAILED: P3F5_MIG71 el up no retiro los objetos o no dejo los mensajes nuevos.', 1;
PRINT 'P3F5_MIG71_UP2_OK';
GO
IF @@TRANCOUNT < 1 THROW 59714, 'TEST FAILED: P3F5_MIG71 la migracion cerro la transaccion de la prueba.', 1;
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0
    THROW 59715, 'TEST FAILED: P3F5_MIG71 la transaccion no se revirtio.', 1;
PRINT 'P3F5_MIG71_ROLLBACK_OK';
GO
