USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- P3 F5 (migracion 71): mensajes del Servicio de Notificaciones y de las confirmaciones y rotulos que el backend ya no lleva solo como texto
-- de respaldo. Mismos textos que MensajesExitoHttp, PoiReporteExcelAdapter y NotificacionesServiceErrores del backend. Idempotente.
--   ERR_NOTIFICACIONES_NO_DISPONIBLE   503 publico cuando el Servicio de Notificaciones no responde.
--   OK_<AREA>_<NNN>                    confirmaciones de operaciones cuyo caso de uso es void (MensajesExitoHttp). OK_REALTIME_001 lleva {0} = suscriptores.
--   RPT_ASISTENCIA_<CLAVE>             rotulos del libro de Excel del reporte de asistencia (PoiReporteExcelAdapter).
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
