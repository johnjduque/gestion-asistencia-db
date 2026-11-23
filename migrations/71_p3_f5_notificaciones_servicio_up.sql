-- ============================================================================
-- MIGRACION UP 71: P3 fase F5 (BD), el correo sale a un servicio propio (Complementos/Notificaciones).
--   Las plantillas, sus versiones, el monitor de la cola y el reintento viven ahora en el Servicio de Notificaciones. Esta migracion:
--   1. Retira PlantillaNotificacion y PlantillaNotificacionMarcador, los 6 SP publicos con su *_interno
--      (usp_consultar_plantillas_notificacion_admin, usp_guardar_plantilla_notificacion, usp_activar_version_plantilla_notificacion,
--      usp_consultar_plantilla_notificacion_activa, usp_consultar_notificaciones_salientes_admin, usp_reintentar_notificacion_saliente)
--      y la vista uv_notificacion_saliente_admin. Los GRANT sobre ellos desaparecen con los objetos; rol_asistencias_runtime se conserva.
--   2. Retira los mensajes NTF_006, NTF_007 y NTF_009 (solo los usaban esos SP). NTF_004 y NTF_008 se conservan: el backend los traduce.
--   3. Siembra ERR_NOTIFICACIONES_NO_DISPONIBLE, las confirmaciones OK_* y los rotulos RPT_ASISTENCIA_* (usuario y tecnico).
--   Se conservan NotificacionSaliente, EstadoNotificacion, TokenVerificacionCorreo y sus SP (outbox y verificacion de correo).
--   MQR_008: su texto de usuario ya es el de DEC-078 (migracion 62); no cambia.
--
-- ANTES DE APLICARLA EN UN ENTORNO CON DATOS REALES: las versiones de plantilla que el administrador creo (version > 1) se pierden con
-- las tablas. Ejecute una sola vez scripts/exportar-plantillas-notificaciones.sql, que las entrega como JSON listo para
-- POST /api/v1/plantillas/{tipo}/versiones del Servicio de Notificaciones:
--   sqlcmd -S <servidor> -d gestionasistenciadb -U <usuario> -P <clave> -C -f 65001 -y 0 -i scripts/exportar-plantillas-notificaciones.sql -o plantillas-personalizadas.txt
--   (la tercera linea del archivo es el JSON; el detalle de uso y de formato esta en el encabezado del script)
-- Esta migracion avisa con PRINT cuantas versiones personalizadas encuentra, pero no se detiene (migrar.ps1 no pasa confirmaciones).
-- Idempotente. Down: 71_p3_f5_notificaciones_servicio_down.sql (recrea todo lo retirado con los mismos cuerpos y la semilla de fabrica;
-- las versiones personalizadas no se recuperan: se importan al servicio desde el JSON exportado, no a la BD).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 71 UP: P3 F5 (plantillas y cola administrativa al Servicio de Notificaciones)';
GO
-- [F5-1] aviso de versiones personalizadas que se van a perder
IF OBJECT_ID(N'dbo.PlantillaNotificacion', N'U') IS NOT NULL
BEGIN
    DECLARE @personalizadas INT;
    EXEC sys.sp_executesql N'SELECT @n = COUNT(*) FROM dbo.PlantillaNotificacion WHERE version > 1 OR creadoPor IS NOT NULL;', N'@n INT OUTPUT', @n = @personalizadas OUTPUT;
    IF @personalizadas > 0
        PRINT CONCAT(N'ADVERTENCIA 71: ', @personalizadas, N' version(es) de plantilla personalizada(s) se pierden con PlantillaNotificacion; deben estar exportadas con scripts/exportar-plantillas-notificaciones.sql.');
END
GO
-- [F5-2] vista, SP (*_interno y publico) y tablas
DROP VIEW IF EXISTS [dbo].[uv_notificacion_saliente_admin];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_plantillas_notificacion_admin];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_plantillas_notificacion_admin_interno];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_guardar_plantilla_notificacion];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_guardar_plantilla_notificacion_interno];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_activar_version_plantilla_notificacion];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_activar_version_plantilla_notificacion_interno];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_plantilla_notificacion_activa];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_plantilla_notificacion_activa_interno];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_notificaciones_salientes_admin];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_consultar_notificaciones_salientes_admin_interno];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_reintentar_notificacion_saliente];
GO
DROP PROCEDURE IF EXISTS [dbo].[usp_reintentar_notificacion_saliente_interno];
GO
DROP TABLE IF EXISTS [dbo].[PlantillaNotificacionMarcador];
GO
DROP TABLE IF EXISTS [dbo].[PlantillaNotificacion];
GO
-- [F5-3] mensajes retirados (NTF_006, NTF_007, NTF_009)
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009');
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('NTF_006', 'NTF_007', 'NTF_009');
GO
-- [F5-4] mensajes nuevos (los mismos de schema/seed/74_p3_f5_mensajes_notificaciones.sql)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ERR_NOTIFICACIONES_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'El servicio de notificaciones no está disponible en este momento. Intenta de nuevo en unos minutos.'),
    ('OK_ADMIN_001', 'SUCCESS', 'BAJO', N'Cierre masivo solicitado correctamente.'),
    ('OK_ASISTENCIA_001', 'SUCCESS', 'BAJO', N'Solicitud de revisión registrada correctamente.'),
    ('OK_ASISTENCIA_002', 'SUCCESS', 'BAJO', N'Asistencias de la sesión registradas correctamente.'),
    ('OK_SESION_001', 'SUCCESS', 'BAJO', N'Sesión cerrada correctamente.'),
    ('OK_SESION_002', 'SUCCESS', 'BAJO', N'Sesión creada correctamente.'),
    ('OK_SESION_003', 'SUCCESS', 'BAJO', N'Sesiones del grupo generadas correctamente.'),
    ('OK_REALTIME_001', 'SUCCESS', 'BAJO', N'Evento reactivo emitido a {0} suscriptores.'),
    ('RPT_ASISTENCIA_CODIGO_GRUPO', 'INFORMATIVO', 'BAJO', N'Código del grupo'),
    ('RPT_ASISTENCIA_GRUPO', 'INFORMATIVO', 'BAJO', N'Grupo'),
    ('RPT_ASISTENCIA_NUMERO_SESION', 'INFORMATIVO', 'BAJO', N'Número de sesión'),
    ('RPT_ASISTENCIA_SESION', 'INFORMATIVO', 'BAJO', N'Sesión'),
    ('RPT_ASISTENCIA_INICIO', 'INFORMATIVO', 'BAJO', N'Inicio'),
    ('RPT_ASISTENCIA_FIN', 'INFORMATIVO', 'BAJO', N'Fin'),
    ('RPT_ASISTENCIA_DOCUMENTO', 'INFORMATIVO', 'BAJO', N'Documento'),
    ('RPT_ASISTENCIA_ESTUDIANTE', 'INFORMATIVO', 'BAJO', N'Estudiante'),
    ('RPT_ASISTENCIA_CORREO', 'INFORMATIVO', 'BAJO', N'Correo'),
    ('RPT_ASISTENCIA_ESTADO', 'INFORMATIVO', 'BAJO', N'Estado de asistencia'),
    ('RPT_ASISTENCIA_OBSERVACION', 'INFORMATIVO', 'BAJO', N'Observación'),
    ('RPT_ASISTENCIA_ESTADO_SIN_REGISTRO', 'INFORMATIVO', 'BAJO', N'SIN REGISTRO'),
    ('RPT_ASISTENCIA_ESTADO_ASISTIO', 'INFORMATIVO', 'BAJO', N'ASISTIÓ'),
    ('RPT_ASISTENCIA_ESTADO_NO_ASISTIO', 'INFORMATIVO', 'BAJO', N'NO ASISTIÓ')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ERR_NOTIFICACIONES_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'Backend (SERVICE_UNAVAILABLE, NotificacionesServiceErrores): el Servicio de Notificaciones no respondió, agotó el tiempo de espera, contestó 5xx, 408 o 429, rechazó la credencial de administración (401 o 403) o su circuit breaker está abierto; los avisos pendientes siguen en la outbox NotificacionSaliente y se reintentan solos.'),
    ('OK_ADMIN_001', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.CIERRE_MASIVO_SOLICITADO: confirmación del cierre masivo (el caso de uso es void).)'),
    ('OK_ASISTENCIA_001', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.SOLICITUD_REVISION_REGISTRADA: confirmación de la radicación de la solicitud de revisión (el caso de uso es void).)'),
    ('OK_ASISTENCIA_002', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.ASISTENCIAS_SESION_REGISTRADAS: confirmación del registro de asistencias de una sesión (el caso de uso es void).)'),
    ('OK_SESION_001', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.SESION_CERRADA: confirmación del cierre de la sesión (el caso de uso es void).)'),
    ('OK_SESION_002', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.SESION_CREADA: respaldo cuando usp_crear_sesion no devuelve mensajeUsuario.)'),
    ('OK_SESION_003', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.SESIONES_GRUPO_GENERADAS: confirmación de la generación de sesiones del grupo.)'),
    ('OK_REALTIME_001', 'SUCCESS', 'BAJO', N'Backend (MensajesExitoHttp.EVENTO_EMITIDO: confirmación del evento de prueba SSE; {0} = número de suscriptores activos.)'),
    ('RPT_ASISTENCIA_CODIGO_GRUPO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Código del grupo» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_GRUPO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Grupo» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_NUMERO_SESION', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Número de sesión» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_SESION', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Sesión» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_INICIO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Inicio» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_FIN', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Fin» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_DOCUMENTO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Documento» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_ESTUDIANTE', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Estudiante» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_CORREO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Correo» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_ESTADO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Estado de asistencia» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_OBSERVACION', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): rótulo de la columna «Observación» del libro de Excel del reporte de asistencia.'),
    ('RPT_ASISTENCIA_ESTADO_SIN_REGISTRO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): texto del estado «SIN REGISTRO» en la columna Estado de asistencia del libro de Excel.'),
    ('RPT_ASISTENCIA_ESTADO_ASISTIO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): texto del estado «ASISTIÓ» en la columna Estado de asistencia del libro de Excel.'),
    ('RPT_ASISTENCIA_ESTADO_NO_ASISTIO', 'INFORMATIVO', 'BAJO', N'Backend (PoiReporteExcelAdapter): texto del estado «NO ASISTIÓ» en la columna Estado de asistencia del libro de Excel.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
