-- ============================================================================
-- MIGRACION DOWN 71: revierte la P3 fase F5. Recrea PlantillaNotificacion y PlantillaNotificacionMarcador con la semilla de fabrica
-- (version 1 de los tipos vigentes y sus marcadores: la de schema/seed 26, 28, 34, 41, 60, 65, 67, 69 y 72 antes de la 71), la vista
-- uv_notificacion_saliente_admin y los 6 SP con su *_interno (mismos cuerpos), con sus GRANT a rol_asistencias_runtime; restituye NTF_006,
-- NTF_007 y NTF_009 y retira ERR_NOTIFICACIONES_NO_DISPONIBLE, OK_* y RPT_ASISTENCIA_*. Las versiones personalizadas no se recuperan
-- (se exportaron al Servicio de Notificaciones). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 71 DOWN: P3 F5 (se recrean plantillas y cola administrativa)';
GO
-- [F5-4] mensajes nuevos fuera
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('ERR_NOTIFICACIONES_NO_DISPONIBLE', 'OK_ADMIN_001', 'OK_ASISTENCIA_001', 'OK_ASISTENCIA_002', 'OK_SESION_001', 'OK_SESION_002', 'OK_SESION_003', 'OK_REALTIME_001', 'RPT_ASISTENCIA_CODIGO_GRUPO', 'RPT_ASISTENCIA_GRUPO', 'RPT_ASISTENCIA_NUMERO_SESION', 'RPT_ASISTENCIA_SESION', 'RPT_ASISTENCIA_INICIO', 'RPT_ASISTENCIA_FIN', 'RPT_ASISTENCIA_DOCUMENTO', 'RPT_ASISTENCIA_ESTUDIANTE', 'RPT_ASISTENCIA_CORREO', 'RPT_ASISTENCIA_ESTADO', 'RPT_ASISTENCIA_OBSERVACION', 'RPT_ASISTENCIA_ESTADO_SIN_REGISTRO', 'RPT_ASISTENCIA_ESTADO_ASISTIO', 'RPT_ASISTENCIA_ESTADO_NO_ASISTIO');
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('ERR_NOTIFICACIONES_NO_DISPONIBLE', 'OK_ADMIN_001', 'OK_ASISTENCIA_001', 'OK_ASISTENCIA_002', 'OK_SESION_001', 'OK_SESION_002', 'OK_SESION_003', 'OK_REALTIME_001', 'RPT_ASISTENCIA_CODIGO_GRUPO', 'RPT_ASISTENCIA_GRUPO', 'RPT_ASISTENCIA_NUMERO_SESION', 'RPT_ASISTENCIA_SESION', 'RPT_ASISTENCIA_INICIO', 'RPT_ASISTENCIA_FIN', 'RPT_ASISTENCIA_DOCUMENTO', 'RPT_ASISTENCIA_ESTUDIANTE', 'RPT_ASISTENCIA_CORREO', 'RPT_ASISTENCIA_ESTADO', 'RPT_ASISTENCIA_OBSERVACION', 'RPT_ASISTENCIA_ESTADO_SIN_REGISTRO', 'RPT_ASISTENCIA_ESTADO_ASISTIO', 'RPT_ASISTENCIA_ESTADO_NO_ASISTIO');
GO
-- [F5-3] mensajes restituidos
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('NTF_006', 'SUCCESS', 'BAJO', N'La plantilla de correo se actualizó y activó correctamente en una nueva versión.'),
    ('NTF_007', 'SUCCESS', 'BAJO', N'La notificación fallida fue reencolada exitosamente para un nuevo intento de envío.'),
    ('NTF_009', 'SUCCESS', 'BAJO', N'Correo de prueba encolado correctamente.')
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
    ('NTF_006', 'SUCCESS', 'BAJO', N'La plantilla de correo se actualizó y activó correctamente en una nueva versión.'),
    ('NTF_007', 'SUCCESS', 'BAJO', N'La notificación fallida fue reencolada exitosamente para un nuevo intento de envío.'),
    ('NTF_009', 'SUCCESS', 'BAJO', N'Correo de prueba encolado correctamente.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- [F5-2] tablas
IF OBJECT_ID('dbo.PlantillaNotificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacion (
        id        UNIQUEIDENTIFIER NOT NULL,
        tipo      VARCHAR(60)      NOT NULL,
        idioma    CHAR(2)          NOT NULL CONSTRAINT DF_PlantillaNotificacion_idioma DEFAULT 'es',
        version   INT              NOT NULL,
        asunto    NVARCHAR(200)    NOT NULL,
        cuerpo    NVARCHAR(4000)   NOT NULL,
        activa    BIT              NOT NULL,
        creadoPor UNIQUEIDENTIFIER NULL,
        creadoEn  DATETIME2(3)     NOT NULL,
        CONSTRAINT PK_PlantillaNotificacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacion_tipo_idioma_version UNIQUE (tipo, idioma, version),
        CONSTRAINT CK_PlantillaNotificacion_version CHECK (version >= 1),
        CONSTRAINT CK_PlantillaNotificacion_tipo CHECK (LEN(TRIM(tipo)) BETWEEN 3 AND 60 AND tipo NOT LIKE '%[^A-Z0-9_]%')
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_PlantillaNotificacion_activa' AND object_id = OBJECT_ID('dbo.PlantillaNotificacion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PlantillaNotificacion_activa
    ON dbo.PlantillaNotificacion (tipo, idioma)
    WHERE activa = 1;
END
GO
GO
IF OBJECT_ID('dbo.PlantillaNotificacionMarcador', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacionMarcador (
        id          UNIQUEIDENTIFIER NOT NULL,
        tipo        VARCHAR(60)      NOT NULL,
        marcador    VARCHAR(40)      NOT NULL,
        descripcion NVARCHAR(200)    NOT NULL,
        ejemplo     NVARCHAR(100)    NOT NULL,
        obligatorio BIT              NOT NULL,
        CONSTRAINT PK_PlantillaNotificacionMarcador PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacionMarcador_tipo_marcador UNIQUE (tipo, marcador),
        CONSTRAINT CK_PlantillaNotificacionMarcador_marcador CHECK (marcador LIKE '[a-zA-Z]%' AND marcador NOT LIKE '%[^a-zA-Z0-9]%')
    );
END
GO
GO
-- semilla de fabrica de plantillas y marcadores
-- (origen: schema/seed/26_plantillas_notificacion.sql)
-- =============================================================================
-- Sembrado Idempotente: PlantillaNotificacionMarcador y PlantillaNotificacion (NOTIF-002A / NOTIF-002B)
-- =============================================================================

MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'estudiante', N'Nombre completo del estudiante retirado', N'Juan Pérez', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'motivo', N'Motivo del retiro registrado por el docente', N'Cancelación académica', 0),

    -- NOTIF-002B: Reclamos de asistencia
    ('RECLAMO_ASISTENCIA_RADICADO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'fecha', N'Fecha de la sesión reclamada', N'2026-11-05', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'motivo', N'Categoría o motivo de la solicitud', N'Incapacidad médica', 0),

    ('RECLAMO_ASISTENCIA_RESUELTO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'fecha', N'Fecha de la sesión reclamada', N'2026-11-05', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'estado', N'Decisión del docente (APROBAR o RECHAZAR)', N'APROBAR', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'observacion', N'Respuesta u observación del docente', N'Soporte médico validado.', 0),

    -- NOTIF-002B: Alertas preventivas y de pérdida
    ('ALERTA_RIESGO_INASISTENCIA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'porcentaje', N'Porcentaje de inasistencia acumulado', N'15.5', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'umbral', N'Umbral de advertencia institucional', N'15', 0),

    ('ALERTA_PERDIDA_INASISTENCIA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'porcentaje', N'Porcentaje de inasistencia acumulado', N'20.0', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'limite', N'Límite reglamentario de pérdida por inasistencia', N'20', 0),

    -- NOTIF-002B: Cierre masivo de período
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'periodo', N'Código o nombre del período académico', N'2026-2', 1),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalEstudiantes', N'Total de matrículas procesadas', N'120', 0),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalAprobados', N'Total de aprobados por asistencia', N'108', 0),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalReprobados', N'Total de reprobados por inasistencia', N'12', 0)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET
        Target.descripcion = Source.descripcion,
        Target.ejemplo     = Source.ejemplo,
        Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
DELETE FROM [dbo].[PlantillaNotificacionMarcador]
WHERE (tipo = 'RECLAMO_ASISTENCIA_RADICADO' AND marcador IN ('fechaSesion', 'causal'))
   OR (tipo = 'RECLAMO_ASISTENCIA_RESUELTO' AND marcador IN ('fechaSesion', 'resultado'));
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'es', 1, N'Retiro del grupo {grupo}', N'Se registró el retiro de {estudiante} del grupo {grupo}.', 1),

    -- NOTIF-002B: Plantillas automáticas
    ('RECLAMO_ASISTENCIA_RADICADO', 'es', 1,
     N'Nueva solicitud de revisión de asistencia en {grupo}',
     N'El estudiante {estudiante} radicó una solicitud de revisión de asistencia para la sesión del {fecha} en el grupo {grupo}. Motivo: {motivo}.',
     1),

    ('RECLAMO_ASISTENCIA_RESUELTO', 'es', 1,
     N'Respuesta a tu solicitud de revisión de asistencia en {grupo}',
     N'Tu solicitud de revisión de asistencia para la sesión del {fecha} en el grupo {grupo} fue resuelta como {estado}. Observaciones del docente: {observacion}.',
     1),

    ('ALERTA_RIESGO_INASISTENCIA', 'es', 1,
     N'Alerta de riesgo de inasistencia en {grupo}',
     N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del 20%.',
     1),

    ('ALERTA_PERDIDA_INASISTENCIA', 'es', 1,
     N'Alerta de pérdida por inasistencia en {grupo}',
     N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido. Por favor contacte a su docente o coordinación académica.',
     1),

    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'es', 1,
     N'Cierre masivo de periodo académico ejecutado',
     N'El cierre masivo del periodo académico {periodo} fue ejecutado exitosamente por el administrador institucional.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET
        Target.asunto = Source.asunto,
        Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/28_plantilla_verificacion_correo.sql)
-- IDENT-001: plantilla v1 y marcadores del aviso de verificacion de correo (idempotente).
-- El marcador {enlace} lo resuelve el canal de correo al entregar (token de un solo uso); nunca se guarda en el outbox.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('VERIFICACION_CORREO', 'nombre', N'Primer nombre del estudiante', N'Juan', 1),
    ('VERIFICACION_CORREO', 'enlace', N'Enlace de verificación de un solo uso (lo genera el sistema al enviar)', N'https://plataforma/verificar-correo#token=...', 1),
    ('VERIFICACION_CORREO', 'grupo', N'Nombre del grupo en el que fue registrado', N'G01 de Ingeniería de Software', 0)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('VERIFICACION_CORREO', 'es', 1,
     N'Verifique su correo institucional',
     N'Hola {nombre}, se registró una cuenta a su nombre en la plataforma de asistencia. Para verificar su correo institucional abra el siguiente enlace: {enlace} . El enlace es de un solo uso y vence pronto. Si usted no esperaba este mensaje, ignórelo.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/34_plantilla_sesion_cancelada.sql)
-- CULM-001 B.1 (CONTRACT §2.12): plantilla de notificacion SESION_CANCELADA (HU047) y sus marcadores. Patron
-- 26_plantillas_notificacion.sql (MERGE idempotente; la version 1 la crea el sistema, creadoPor NULL). El mismo texto
-- por defecto vive en PlantillaPorDefectoCatalogo del backend. La cancelacion automatica por FESTIVO no notifica.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_CANCELADA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('SESION_CANCELADA', 'asignatura', N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_CANCELADA', 'grupo',      N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_CANCELADA', 'fecha',      N'Fecha de la sesión cancelada', N'2026-11-10', 1),
    ('SESION_CANCELADA', 'horaInicio', N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_CANCELADA', 'horaFin',    N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_CANCELADA', 'motivo',     N'Motivo de la cancelación registrado por el docente', N'Calamidad doméstica del docente', 1),
    ('SESION_CANCELADA', 'docente',    N'Nombre completo del docente titular', N'María Rostagno', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET
        Target.descripcion = Source.descripcion,
        Target.ejemplo     = Source.ejemplo,
        Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_CANCELADA', 'es', 1,
     N'Clase cancelada: {asignatura} ({fecha})',
     N'Hola {estudiante}. El docente {docente} canceló la clase de {asignatura} del grupo {grupo} programada para el {fecha} de {horaInicio} a {horaFin}. Motivo: {motivo}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET
        Target.asunto = Source.asunto,
        Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/41_culm001_c_plantillas_notificacion.sql)
-- CULM-001 C.1 (CONTRACT §2.9): plantillas de notificacion de la cancelacion por inasistencia. Patron 34_plantilla_sesion_cancelada.sql.
-- Marcadores: MERGE idempotente. Plantillas nuevas: solo se insertan (no pisan ediciones del administrador). Las dos ALERTA_*
-- existentes pasan a {umbral}/{limite} unicamente si conservan el texto por defecto anterior (SUPUESTO-C-16).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('ALERTA_RIESGO_INASISTENCIA',  'limite',      N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('REVISION_CANCELACION_PENDIENTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'estudiante',  N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'porcentaje',  N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'limite',      N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('PROPUESTA_CANCELACION', 'resolutor',    N'Nombre completo de quien resuelve', N'Ana Gómez', 1),
    ('PROPUESTA_CANCELACION', 'estudiante',   N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('PROPUESTA_CANCELACION', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('PROPUESTA_CANCELACION', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('PROPUESTA_CANCELACION', 'porcentaje',   N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('PROPUESTA_CANCELACION', 'limite',       N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('PROPUESTA_CANCELACION', 'motivo',       N'Motivo registrado por el docente', N'Sin asistencia en las últimas semanas', 1),
    ('PROPUESTA_CANCELACION', 'escalamiento', N'Texto que explica la asignación a la decanatura (vacío si no aplica)', N'', 0),
    ('CANCELACION_APROBADA', 'destinatario',  N'Nombre completo de quien recibe el correo', N'Juan Pérez', 1),
    ('CANCELACION_APROBADA', 'estudiante',    N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('CANCELACION_APROBADA', 'grupo',         N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('CANCELACION_APROBADA', 'porcentaje',    N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('CANCELACION_APROBADA', 'motivo',        N'Motivo de la resolución', N'Pérdida por inasistencia', 1),
    ('CANCELACION_APROBADA', 'resolutor',     N'Nombre completo de quien resolvió', N'Ana Gómez', 1),
    ('CANCELACION_RECHAZADA', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('CANCELACION_RECHAZADA', 'estudiante',   N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('CANCELACION_RECHAZADA', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('CANCELACION_RECHAZADA', 'motivo',       N'Motivo de la resolución', N'Se acepta una justificación', 1),
    ('CANCELACION_RECHAZADA', 'resolutor',    N'Nombre completo de quien resolvió', N'Ana Gómez', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('REVISION_CANCELACION_PENDIENTE', 'es', 1,
     N'Revisión de cancelación pendiente: {estudiante} en {grupo}',
     N'Hola {docente}. El estudiante {estudiante} alcanzó el {porcentaje}% de inasistencia en {grupo} (límite {limite}%). Revisa el caso desde la planilla del grupo: puedes mantenerlo o proponer su cancelación con un motivo.',
     1),
    ('PROPUESTA_CANCELACION', 'es', 1,
     N'Propuesta de cancelación por inasistencia: {estudiante} en {grupo}',
     N'Hola {resolutor}. El docente {docente} propone cancelar por inasistencia a {estudiante} en {grupo}: {porcentaje}% de inasistencia (límite {limite}%). Motivo: {motivo}. {escalamiento}',
     1),
    ('CANCELACION_APROBADA', 'es', 1,
     N'Cancelación por inasistencia en {grupo}',
     N'Hola {destinatario}. Se aprobó la cancelación por inasistencia de {estudiante} en {grupo} ({porcentaje}% de inasistencia). Motivo: {motivo}. Resolvió: {resolutor}.',
     1),
    ('CANCELACION_RECHAZADA', 'es', 1,
     N'Propuesta de cancelación rechazada: {estudiante} en {grupo}',
     N'Hola {docente}. Se rechazó la propuesta de cancelación de {estudiante} en {grupo}; el estudiante sigue activo. Motivo: {motivo}. Resolvió: {resolutor}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- SUPUESTO-C-16: cuerpo de las ALERTA_* a {umbral}/{limite} solo si conserva el texto por defecto de 26_plantillas_notificacion.sql.
UPDATE [dbo].[PlantillaNotificacion]
SET cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del {limite}%.'
WHERE tipo = 'ALERTA_RIESGO_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del 20%.';
GO
UPDATE [dbo].[PlantillaNotificacion]
SET cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido del {limite}%. Por favor contacte a su docente o coordinación académica.'
WHERE tipo = 'ALERTA_PERDIDA_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido. Por favor contacte a su docente o coordinación académica.';
GO
-- (origen: schema/seed/60_sesiones_manuales_plantillas.sql)
-- CULM-001 / DEC-064: plantillas de notificacion de una sesion creada manualmente por el docente. Patron 34_plantilla_sesion_cancelada.sql
-- (MERGE idempotente; la version 1 la crea el sistema, creadoPor NULL; no pisa ediciones del administrador). El mismo texto por defecto
-- vive en PlantillaPorDefectoCatalogo del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'estudiante',  N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'coordinador', N'Nombre completo del coordinador', N'Ana Gómez', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'es', 1,
     N'Nueva sesión de clase: {asignatura} ({fecha})',
     N'Hola {estudiante}. El docente {docente} programó una sesión adicional de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}.',
     1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'es', 1,
     N'Sesión creada manualmente: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} creó manualmente una sesión de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Si no corresponde, puede cancelarla desde su vista de sesiones.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- CULM-001 / DEC-065 (2): plantillas de la solicitud de sesion extraordinaria con aval del coordinador (mismo formato y marcadores que las
-- de DEC-064). SESION_SOLICITUD_CREADA_COORDINADOR avisa al coordinador la solicitud; SESION_SOLICITUD_APROBADA_DOCENTE y
-- SESION_SOLICITUD_RECHAZADA_DOCENTE avisan al docente la decision (la rechazada agrega motivo y observacion). Idempotente.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'coordinador', N'Nombre completo del coordinador', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'asignatura',   N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'fecha',        N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'horaInicio',   N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'horaFin',      N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'coordinador',  N'Nombre completo del coordinador que decidió', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'coordinador', N'Nombre completo del coordinador que decidió', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'motivo',      N'Motivo del rechazo (catálogo de motivos)', N'Sesión fuera del calendario académico', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'observacion', N'Observación del coordinador (puede ir vacía)', N'Reprogramar la próxima semana', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'es', 1,
     N'Solicitud de sesión extraordinaria: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} solicitó una sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. La sesión queda pendiente de su aprobación; puede aprobarla o rechazarla desde su vista de solicitudes.',
     1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'es', 1,
     N'Solicitud aprobada: {asignatura} ({fecha})',
     N'Hola {docente}. {coordinador} aprobó su solicitud de sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Ya puede tomar asistencia en ella y los estudiantes fueron notificados.',
     1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'es', 1,
     N'Solicitud rechazada: {asignatura} ({fecha})',
     N'Hola {docente}. {coordinador} rechazó su solicitud de sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Motivo: {motivo}. {observacion}',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/65_ident002_activacion_cuentas.sql)
-- IDENT-002: activacion de cuentas registradas por otra persona (sin contrasena en el registro). Plantilla v1 y marcadores
-- del aviso ACTIVACION_CUENTA y mensajes VCE_009, ACT_001 y ACT_002 (usuario y tecnicos). Idempotente.
-- El marcador {enlace} lo resuelve el canal de correo al entregar (token de un solo uso, mismo mecanismo de IDENT-001).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('ACTIVACION_CUENTA', 'nombre', N'Primer nombre de la persona registrada', N'Juan', 1),
    ('ACTIVACION_CUENTA', 'enlace', N'Enlace de activación de un solo uso (lo genera el sistema al enviar)', N'https://plataforma/activar-cuenta#token=...', 1),
    ('ACTIVACION_CUENTA', 'rol', N'Rol con el que fue registrada la cuenta', N'coordinador(a) de programa', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('ACTIVACION_CUENTA', 'es', 1,
     N'Active su cuenta en la plataforma de asistencia',
     N'Hola {nombre}, se registró una cuenta a su nombre como {rol} en la plataforma de asistencia de la Universidad Católica de Oriente. Para activarla y definir su contraseña abra el siguiente enlace: {enlace} . El enlace es de un solo uso y vence pronto; si vence, pida a quien lo registró que se lo envíe de nuevo. Si usted no esperaba este mensaje, ignórelo.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/67_ata_plantilla_falta_sesion.sql)
-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): plantilla del aviso de falta por sesion al estudiante (un correo por estudiante y sesion).
-- Patron 60_sesiones_manuales_plantillas.sql: MERGE idempotente; la version 1 la crea el sistema (creadoPor NULL). El mismo texto por defecto
-- vive en PlantillaPorDefectoCatalogo del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'estudiante',         N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'asignatura',         N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'grupo',              N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'fecha',              N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'horaInicio',         N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'horaFin',            N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'detalleFaltas',      N'Falta general o lista de tomas en falta con su hora (hora institucional)', N'toma 1 (08:15), toma 3 (09:40)', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'fechaLimiteReclamo', N'Fecha límite para radicar el reclamo (hora institucional)', N'16/11/2026', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'enlaceReclamo',      N'Enlace a la materia en la plataforma, donde se radica el reclamo', N'https://asistencia.uco.edu.co/app/estudiante/mis-materias/materias', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'es', 1,
     N'Registro de inasistencia: {asignatura} ({fecha})',
     N'Hola {estudiante}. En la sesión de {asignatura} del grupo {grupo} del {fecha} de {horaInicio} a {horaFin} quedó registrada inasistencia: {detalleFaltas}. Si consideras que hay un error, puedes radicar un reclamo por cada toma hasta el {fechaLimiteReclamo} desde {enlaceReclamo}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/69_notoma_parametros_plantilla.sql)
-- NOTOMA-001: plantilla del aviso a la coordinacion cuando el docente no tomo asistencia en una sesion (un correo por coordinador y sesion).
-- Patron 67_ata_plantilla_falta_sesion.sql: MERGE idempotente; la version 1 la crea el sistema (creadoPor NULL). El mismo texto por defecto
-- vive en notification/templates/SESION_SIN_TOMA_COORDINADOR.es.properties del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_SIN_TOMA_COORDINADOR', 'coordinador',    N'Nombre completo del coordinador destinatario', N'Laura Martínez', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'asignatura',     N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'grupo',          N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'fecha',          N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'horaInicio',     N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'horaFin',        N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'docente',        N'Nombre completo del docente titular del grupo', N'María Gómez', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'enlaceSesiones', N'Enlace a la consulta de asistencia del coordinador en la plataforma', N'https://asistencia.uco.edu.co/app/coordinador/asistencia', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_SIN_TOMA_COORDINADOR', 'es', 1,
     N'Sesión sin toma de asistencia: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} no tomó asistencia en la sesión de {asignatura} del grupo {grupo} del {fecha} de {horaInicio} a {horaFin}. Este aviso es solo informativo; puede revisar el grupo en {enlaceSesiones}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- (origen: schema/seed/72_receso_academico_plantillas.sql)
-- DEC-081 (2026-11-21): plantillas del aviso de clases canceladas por un dia de receso academico (un correo por persona con el resumen
-- de sus clases canceladas). Patron 60_sesiones_manuales_plantillas.sql (MERGE idempotente; version 1 creada por el sistema; no pisa
-- ediciones del administrador). El mismo texto por defecto vive en los recursos de plantillas del backend. Migracion 68.
-- {clases} es una sola linea: las clases separadas por "; " (el motor no convierte saltos de linea dentro de un valor).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'fecha',      N'Fecha del receso académico (dd/MM/yyyy, hora institucional)', N'10/11/2026', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'motivo',     N'Motivo del receso académico', N'Jornada institucional', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'clases',     N'Clases canceladas del estudiante ese día (asignatura, grupo y hora), separadas por punto y coma', N'Ingeniería de Software, G01, 08:00 a 10:00; Bases de Datos, G02, 10:00 a 12:00', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'docente',       N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'fecha',         N'Fecha del receso académico (dd/MM/yyyy, hora institucional)', N'10/11/2026', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'motivo',        N'Motivo del receso académico', N'Jornada institucional', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'clases',        N'Clases canceladas del docente ese día (asignatura, grupo y hora), separadas por punto y coma', N'Ingeniería de Software, G01, 08:00 a 10:00; Bases de Datos, G02, 10:00 a 12:00', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'es', 1,
     N'Clases canceladas por receso académico ({fecha})',
     N'Hola {estudiante}. La institución declaró receso académico el {fecha}. Motivo: {motivo}. Estas clases quedaron canceladas y no cuentan como inasistencia: {clases}.',
     1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'es', 1,
     N'Clases canceladas por receso académico ({fecha})',
     N'Hola {docente}. La institución declaró receso académico el {fecha}. Motivo: {motivo}. Estas clases suyas quedaron canceladas y no requieren toma de asistencia: {clases}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
-- vista
GO

-- =============================================================================
-- Vista: [dbo].[uv_notificacion_saliente_admin]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Administrador Institucional
-- =============================================================================
CREATE OR ALTER VIEW [dbo].[uv_notificacion_saliente_admin]
AS
SELECT
    id                    = n.id,
    tipo                  = n.tipo,
    asunto                = n.asunto,
    codigoEstado          = e.codigo,
    nombreEstado          = e.nombre,
    esTerminal            = e.esTerminal,
    cantidadDestinatarios = CASE WHEN ISJSON(n.destinatarios) = 1 THEN (SELECT COUNT(*) FROM OPENJSON(n.destinatarios)) ELSE 0 END,
    intentos              = n.intentos,
    creadoEn              = n.creadoEn,
    proximoIntentoEn      = n.proximoIntentoEn,
    entregadoEn           = n.entregadoEn,
    codigoError           = n.codigoError,
    detalleError          = n.detalleError,
    idCorrelacion         = n.idCorrelacion
FROM dbo.NotificacionSaliente n
INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado;
GO
GO
-- procedimientos (cada *_interno antes de su fachada)
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantillas_notificacion_admin_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Consulta interna atomica de versiones de plantillas y marcadores declarados.
-- Salida:
--   Result set 2: Versiones de plantillas filtradas por idioma (tipo ASC, version DESC).
--   Result set 3: Marcadores declarados (tipo ASC, obligatorio DESC, marcador ASC).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantillas_notificacion_admin_interno]
(
    @idioma CHAR(2) = 'es'
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idiomaDef CHAR(2) = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

    -- Result set 2: Tipos con su version activa actual
    SELECT
        tipo          = p.tipo,
        idioma        = p.idioma,
        versionActiva = p.[version],
        asuntoActivo  = p.asunto,
        cuerpoActivo  = p.cuerpo,
        actualizadoEn = p.creadoEn
    FROM dbo.PlantillaNotificacion p
    WHERE p.idioma = @idiomaDef
      AND p.activa = 1
    ORDER BY p.tipo ASC;

    -- Result set 3: Marcadores declarados
    SELECT
        tipo        = m.tipo,
        marcador    = m.marcador,
        descripcion = m.descripcion,
        ejemplo     = m.ejemplo,
        obligatorio = m.obligatorio
    FROM dbo.PlantillaNotificacionMarcador m
    ORDER BY m.tipo ASC, m.obligatorio DESC, m.marcador ASC;

    -- Result set 4: Historial completo de versiones por tipo
    SELECT
        id        = p.id,
        tipo      = p.tipo,
        idioma    = p.idioma,
        [version] = p.[version],
        asunto    = p.asunto,
        cuerpo    = p.cuerpo,
        activa    = p.activa,
        creadoEn  = p.creadoEn
    FROM dbo.PlantillaNotificacion p
    WHERE p.idioma = @idiomaDef
    ORDER BY p.tipo ASC, p.[version] DESC;
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantillas_notificacion_admin]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Fachada publica para que el Administrador Institucional consulte todas
--         las versiones de plantillas y sus marcadores.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): Versiones de plantillas
--   Result set 3 (cuando estadoResultado=1): Marcadores declarados
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantillas_notificacion_admin]
(
    @idioma            CHAR(2)          = 'es',
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idiomaDef                CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. El usuario ejecutor es obligatorio: sin el no se consulta (nunca se omite el RBAC)
        IF @estadoResultado = 1 AND @idUsuarioEjecutorDefecto = @guidVacio
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Preparar mensaje de exito
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'PlantillaNotificacion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: plantillas y marcadores
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_plantillas_notificacion_admin_interno
            @idioma = @idiomaDef;
    END
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_guardar_plantilla_notificacion_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Operacion atomica de insercion de nueva version y activacion de plantilla.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_plantilla_notificacion_interno]
(
    @tipo                    VARCHAR(60),
    @idioma                  CHAR(2),
    @asunto                  NVARCHAR(200),
    @cuerpo                  NVARCHAR(4000),
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idCreado                UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000)   OUTPUT,
    @estadoResultado         BIT              OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;
    SET @idCreado                = NULL;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_guardar_plantilla_notif;
            SET @savepointCreado = 1;
        END

        -- 1. Bloqueo protector de concurrencia y calculo de nueva version
        DECLARE @maxVersion INT;
        SELECT @maxVersion = MAX([version])
        FROM dbo.PlantillaNotificacion WITH (UPDLOCK, HOLDLOCK)
        WHERE tipo = @tipo AND idioma = @idioma;

        DECLARE @nuevaVersion INT = COALESCE(@maxVersion, 1) + 1;
        IF @maxVersion IS NULL
            SET @nuevaVersion = 2;

        -- 2. Desactivar version activa previa
        UPDATE dbo.PlantillaNotificacion
        SET activa = 0
        WHERE tipo = @tipo AND idioma = @idioma AND activa = 1;

        -- 3. Insertar la nueva version como activa
        SET @idCreado = NEWID();

        INSERT INTO dbo.PlantillaNotificacion (
            id,
            tipo,
            idioma,
            [version],
            asunto,
            cuerpo,
            activa,
            creadoPor,
            creadoEn
        )
        VALUES (
            @idCreado,
            @tipo,
            @idioma,
            @nuevaVersion,
            @asunto,
            @cuerpo,
            1,
            @idUsuarioEjecutor,
            SYSUTCDATETIME()
        );

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_006',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Version: ', @nuevaVersion, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_guardar_plantilla_notif;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @idCreado = NULL;
    END CATCH
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_guardar_plantilla_notificacion]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Fachada publica para que el Administrador guarde y active una nueva version de plantilla.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): Fila creada (id, tipo, idioma, version, asunto, cuerpo, activa, creadoEn)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_plantilla_notificacion]
(
    @tipo              NVARCHAR(100)    = NULL,
    @idioma            CHAR(2)          = 'es',
    @asunto            NVARCHAR(400)    = NULL,
    @cuerpo            NVARCHAR(MAX)    = NULL,
    @creadoPor         UNIQUEIDENTIFIER = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecutorEfectivo         UNIQUEIDENTIFIER = COALESCE(@idUsuarioEjecutor, @creadoPor);
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@ejecutorEfectivo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idiomaDef                CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');
    DECLARE @tipoDef                  VARCHAR(60)      = NULL;
    DECLARE @asuntoRaw                NVARCHAR(200)    = NULL;
    DECLARE @cuerpoRaw                NVARCHAR(4000)   = NULL;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT              = 1;
    DECLARE @idCreado                UNIQUEIDENTIFIER = NULL;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar idUsuarioEjecutor obligatorio
        IF @estadoResultado = 1 AND (@ejecutorEfectivo IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 5. Validar asunto (1..200 caracteres no nulo ni vacio)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @asuntoInput NVARCHAR(400) = TRIM(@asunto);
            IF @asuntoInput IS NULL OR LEN(@asuntoInput) = 0 OR LEN(@asuntoInput) > 200
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Asunto de plantilla invalido (1-200 caracteres). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @asuntoRaw = CAST(@asuntoInput AS NVARCHAR(200));
            END
        END

        -- 6. Validar cuerpo (1..4000 caracteres no nulo ni vacio)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @cuerpoInput NVARCHAR(MAX) = TRIM(@cuerpo);
            IF @cuerpoInput IS NULL OR LEN(@cuerpoInput) = 0 OR LEN(@cuerpoInput) > 4000
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Cuerpo de plantilla invalido (1-4000 caracteres). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @cuerpoRaw = CAST(@cuerpoInput AS NVARCHAR(4000));
            END
        END

        -- 7. Validar que el tipo tenga al menos un marcador declarado
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador WHERE tipo = @tipoDef)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' El tipo no tiene marcadores declarados. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 8. Validar marcadores obligatorios y tokens permitidos en asunto + cuerpo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @textoCompleto NVARCHAR(MAX) = CONCAT(@asuntoRaw, N' ', @cuerpoRaw);

            -- Regla 1: Todo marcador obligatorio debe estar presente
            IF EXISTS (
                SELECT 1
                FROM dbo.PlantillaNotificacionMarcador m
                WHERE m.tipo = @tipoDef
                  AND m.obligatorio = 1
                  AND CHARINDEX(CONCAT(N'{', m.marcador, N'}'), @textoCompleto) = 0
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Faltan marcadores obligatorios en el texto. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- Regla 2: Todo token {...} debe ser un marcador declarado para el tipo (y llaves balanceadas)
            IF @estadoResultado = 1
            BEGIN
                DECLARE @posAbre INT = CHARINDEX('{', @textoCompleto);
                DECLARE @posCierra INT;
                DECLARE @proximoAbre INT;
                DECLARE @token NVARCHAR(100);
                DECLARE @tokensInvalidos BIT = 0;

                WHILE @posAbre > 0 AND @tokensInvalidos = 0
                BEGIN
                    SET @posCierra = CHARINDEX('}', @textoCompleto, @posAbre + 1);
                    IF @posCierra = 0
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @proximoAbre = CHARINDEX('{', @textoCompleto, @posAbre + 1);
                    IF @proximoAbre > 0 AND @proximoAbre < @posCierra
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @token = SUBSTRING(@textoCompleto, @posAbre + 1, @posCierra - @posAbre - 1);

                    IF LEN(TRIM(@token)) = 0 OR NOT EXISTS (
                        SELECT 1
                        FROM dbo.PlantillaNotificacionMarcador m
                        WHERE m.tipo = @tipoDef AND m.marcador = @token
                    )
                    BEGIN
                        SET @tokensInvalidos = 1;
                        BREAK;
                    END

                    SET @posAbre = CHARINDEX('{', @textoCompleto, @posCierra + 1);
                END

                IF @tokensInvalidos = 0
                BEGIN
                    IF (LEN(@textoCompleto) - LEN(REPLACE(@textoCompleto, '{', ''))) <> (LEN(@textoCompleto) - LEN(REPLACE(@textoCompleto, '}', '')))
                    BEGIN
                        SET @tokensInvalidos = 1;
                    END
                END

                IF @tokensInvalidos = 1
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'NTF_004',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Contiene marcadores no declarados o llaves invalidas. Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- 9. Insercion atomica delegada
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_guardar_plantilla_notificacion_interno
                @tipo = @tipoDef,
                @idioma = @idiomaDef,
                @asunto = @asuntoRaw,
                @cuerpo = @cuerpoRaw,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @idCreado = @idCreado OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @idCreado = NULL;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result set 2: version creada
    IF @estadoResultado = 1
    BEGIN
        SELECT
            id        = p.id,
            tipo      = p.tipo,
            idioma    = p.idioma,
            [version] = p.[version],
            asunto    = p.asunto,
            cuerpo    = p.cuerpo,
            activa    = p.activa,
            creadoEn  = p.creadoEn
        FROM dbo.PlantillaNotificacion p
        WHERE p.id = @idCreado;
    END
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_activar_version_plantilla_notificacion_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Operacion atomica de activacion de una version existente de plantilla.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_activar_version_plantilla_notificacion_interno]
(
    @tipo                    VARCHAR(60),
    @idioma                  CHAR(2),
    @version                 INT,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- 1. Verificar si la version existe para el tipo e idioma
        IF NOT EXISTS (
            SELECT 1 
            FROM dbo.PlantillaNotificacion 
            WHERE tipo = @tipo AND idioma = @idioma AND [version] = @version
        )
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Version no encontrada: ', @version, ' Tipo: ', @tipo, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_activar_version_plantilla;
            SET @savepointCreado = 1;
        END

        -- 2. Bloqueo protector de concurrencia
        -- Se asigna a una variable: un SELECT suelto emitiria un result set extra antes de la tupla canonica.
        DECLARE @bloqueoTomado INT;
        SELECT @bloqueoTomado = 1
        FROM dbo.PlantillaNotificacion WITH (UPDLOCK, HOLDLOCK)
        WHERE tipo = @tipo AND idioma = @idioma;

        -- 3. Desactivar version activa previa
        UPDATE dbo.PlantillaNotificacion
        SET activa = 0
        WHERE tipo = @tipo AND idioma = @idioma AND activa = 1 AND [version] <> @version;

        -- 4. Activar la version solicitada
        UPDATE dbo.PlantillaNotificacion
        SET activa = 1
        WHERE tipo = @tipo AND idioma = @idioma AND [version] = @version;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_006',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Activada version: ', @version, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_activar_version_plantilla;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_activar_version_plantilla_notificacion]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Fachada publica para que el Administrador active una version existente de plantilla.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_activar_version_plantilla_notificacion]
(
    @tipo              NVARCHAR(100)    = NULL,
    @idioma            CHAR(2)          = 'es',
    @version           INT              = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idiomaDef                CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');
    DECLARE @tipoDef                  VARCHAR(60)      = NULL;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar idUsuarioEjecutor obligatorio
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 5. Validar version (>= 1)
        IF @estadoResultado = 1 AND (@version IS NULL OR @version < 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Version invalida (debe ser mayor o igual a 1). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 6. Activacion atomica delegada
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_activar_version_plantilla_notificacion_interno
                @tipo = @tipoDef,
                @idioma = @idiomaDef,
                @version = @version,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantilla_notificacion_activa_interno]
-- Capacidad: Plantillas de Notificacion (NOTIF-002A)
-- Ambito: Consulta interna atomica de plantilla activa y marcadores del tipo.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantilla_notificacion_activa_interno]
(
    @tipo   VARCHAR(60),
    @idioma CHAR(2)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Result set 2: Plantilla activa (0 o 1 fila)
    SELECT TOP 1
        [version] = p.[version],
        [asunto]  = p.[asunto],
        [cuerpo]  = p.[cuerpo]
    FROM dbo.PlantillaNotificacion p
    WHERE p.tipo = @tipo
      AND p.idioma = @idioma
      AND p.activa = 1;

    -- Result set 3: Marcadores declarados para el tipo
    SELECT
        [marcador]    = m.[marcador],
        [obligatorio] = m.[obligatorio]
    FROM dbo.PlantillaNotificacionMarcador m
    WHERE m.tipo = @tipo
    ORDER BY m.marcador ASC;
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantilla_notificacion_activa]
-- Capacidad: Plantillas de Notificacion (NOTIF-002A)
-- Ambito: Fachada publica tecnica para consultar la plantilla activa de un tipo
--         y sus marcadores declarados. Excepcion RBAC documentada (solo runtime,
--         igual que NOTIF-001 D9).
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): 0 o 1 fila (version, asunto, cuerpo)
--   Result set 3 (cuando estadoResultado=1): lista de marcadores (marcador, obligatorio)
-- CULM-001 D.9-a (F-ADM-027): con @validarExistencia = 1 (vista previa del administrador) un tipo que no existe en
-- PlantillaNotificacion ni en PlantillaNotificacionMarcador devuelve NTF_021 (404). Con 0 (defecto: el despachador de correos) un
-- tipo sin plantilla sigue devolviendo 0 filas y el backend usa su plantilla por defecto.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantilla_notificacion_activa]
(
    @tipo          NVARCHAR(100)    = NULL,
    @idioma        CHAR(2)          = 'es',
    @idCorrelacion UNIQUEIDENTIFIER = NULL,
    @validarExistencia BIT          = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tipoDef              VARCHAR(60)      = NULL;
    DECLARE @idiomaDef            CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @validarExistencia = 1
               AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion p WHERE p.tipo = @tipoRaw)
               AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador m WHERE m.tipo = @tipoRaw)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_021',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido (3-60 caracteres A-Z, 0-9, _). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 3. Preparar mensaje de exito GEN_003
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'PlantillaNotificacion',
                @p_param2 = @tipoDef,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: plantilla y marcadores cuando la validacion fue exitosa
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_plantilla_notificacion_activa_interno
            @tipo = @tipoDef,
            @idioma = @idiomaDef;
    END
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_notificaciones_salientes_admin_interno]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Consulta interna paginada de notificaciones salientes y resumen por estado.
-- Salida:
--   Result set 2: Notificaciones paginadas con totalRegistros (creadoEn DESC)
--   Result set 3: Resumen de totales por estado (codigoEstado, total)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_notificaciones_salientes_admin_interno]
(
    @codigoEstado NVARCHAR(40) = NULL,
    @tipo         NVARCHAR(60) = NULL,
    @numeroPagina INT          = 1,
    @tamanoPagina INT          = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @codigoEstadoDef NVARCHAR(40) = CASE WHEN UPPER(TRIM(@codigoEstado)) = 'TODOS' THEN NULL ELSE NULLIF(TRIM(@codigoEstado), '') END;
    DECLARE @tipoDef         NVARCHAR(60) = CASE WHEN UPPER(TRIM(@tipo)) = 'TODOS' THEN NULL ELSE NULLIF(TRIM(@tipo), '') END;
    DECLARE @numPagDef       INT          = CASE WHEN COALESCE(@numeroPagina, 1) <= 1 THEN 1 ELSE @numeroPagina END;
    DECLARE @tamPagDef       INT          = COALESCE(@tamanoPagina, 20);
    DECLARE @offset          INT          = (@numPagDef - 1) * @tamPagDef;

    DECLARE @totalElementos BIGINT = (
        SELECT COUNT(*)
        FROM dbo.uv_notificacion_saliente_admin
        WHERE (@codigoEstadoDef IS NULL OR codigoEstado = @codigoEstadoDef)
          AND (@tipoDef IS NULL OR tipo = @tipoDef)
    );
    DECLARE @totalPaginas INT = CASE WHEN @totalElementos = 0 THEN 1 ELSE CEILING(CAST(@totalElementos AS FLOAT) / @tamPagDef) END;

    -- Result set 2: Lista paginada
    SELECT
        id,
        tipo,
        asunto,
        codigoEstado,
        nombreEstado,
        esTerminal,
        cantidadDestinatarios,
        intentos,
        creadoEn,
        proximoIntentoEn,
        entregadoEn,
        codigoError,
        detalleError,
        idCorrelacion
    FROM dbo.uv_notificacion_saliente_admin
    WHERE (@codigoEstadoDef IS NULL OR codigoEstado = @codigoEstadoDef)
      AND (@tipoDef IS NULL OR tipo = @tipoDef)
    ORDER BY creadoEn DESC
    OFFSET @offset ROWS
    FETCH NEXT @tamPagDef ROWS ONLY;

    -- Result set 3: Metadatos de paginacion
    SELECT
        totalElementos = @totalElementos,
        totalPaginas   = @totalPaginas;

    -- Result set 4: Resumen de totales por estado (fila unica de 5 columnas)
    SELECT
        pendientes            = COALESCE(SUM(CASE WHEN codigoEstado = 'PENDIENTE' THEN 1 ELSE 0 END), 0),
        reservadas            = COALESCE(SUM(CASE WHEN codigoEstado = 'RESERVADA' THEN 1 ELSE 0 END), 0),
        entregadas            = COALESCE(SUM(CASE WHEN codigoEstado = 'ENTREGADA' THEN 1 ELSE 0 END), 0),
        fallidasReintentables = COALESCE(SUM(CASE WHEN codigoEstado = 'FALLIDA_REINTENTABLE' THEN 1 ELSE 0 END), 0),
        fallidasDefinitivas   = COALESCE(SUM(CASE WHEN codigoEstado = 'FALLIDA_DEFINITIVA' THEN 1 ELSE 0 END), 0)
    FROM dbo.uv_notificacion_saliente_admin;
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_notificaciones_salientes_admin]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Fachada publica para que el Administrador consulte la cola outbox y su resumen.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): Notificaciones paginadas con totalRegistros (creadoEn DESC)
--   Result set 3 (cuando estadoResultado=1): Resumen de totales por estado (codigoEstado, total)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_notificaciones_salientes_admin]
(
    @estado            NVARCHAR(40)     = NULL,
    @codigoEstado      NVARCHAR(40)     = NULL,
    @tipo              NVARCHAR(60)     = NULL,
    @numeroPagina      INT              = 1,
    @tamanoPagina      INT              = 20,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoEstadoDef          NVARCHAR(40)     = COALESCE(NULLIF(TRIM(@estado), ''), NULLIF(TRIM(@codigoEstado), ''));
    DECLARE @tipoDef                  NVARCHAR(60)     = NULLIF(TRIM(@tipo), '');
    DECLARE @numPagDef                INT              = COALESCE(@numeroPagina, 1);
    DECLARE @tamPagDef                INT              = COALESCE(@tamanoPagina, 20);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. El usuario ejecutor es obligatorio: sin el no se consulta (nunca se omite el RBAC)
        IF @estadoResultado = 1 AND @idUsuarioEjecutorDefecto = @guidVacio
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar parametros de paginacion (pagina >= 0, tamano entre 1 y 100)
        IF @estadoResultado = 1 AND (@numPagDef < 0 OR @tamPagDef < 1 OR @tamPagDef > 100)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numPagDef,
                @p_param2 = @tamPagDef,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Paginacion fuera de rango (1-100). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 5. Mensaje de exito
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'NotificacionSaliente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: lista paginada y resumen
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_notificaciones_salientes_admin_interno
            @codigoEstado = @codigoEstadoDef,
            @tipo         = @tipoDef,
            @numeroPagina = @numPagDef,
            @tamanoPagina = @tamPagDef;
    END
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reintentar_notificacion_saliente_interno]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Operacion atomica de transicion de estado a PENDIENTE para reintento manual.
-- CULM-001 D.9-a (F-ADM-027): una notificacion inexistente devuelve NTF_020 ("La notificacion no existe.", 404).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_reintentar_notificacion_saliente_interno]
(
    @idNotificacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- 1. Validar existencia
        IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idNotificacion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_020',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_reintentar_notif_saliente;
            SET @savepointCreado = 1;
        END

        -- 2. Validar estado actual con bloqueo protector (UPDLOCK, HOLDLOCK)
        DECLARE @codigoEstado VARCHAR(30);
        SELECT @codigoEstado = e.codigo
        FROM dbo.NotificacionSaliente n WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
        WHERE n.id = @idNotificacion;

        IF @codigoEstado NOT IN ('FALLIDA_DEFINITIVA', 'FALLIDA_REINTENTABLE')
        BEGIN
            IF @savepointCreado = 1 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
            ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_008',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Estado actual: ', @codigoEstado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        -- 3. Resetear parametros y pasar a PENDIENTE
        DECLARE @idEstadoPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');

        UPDATE dbo.NotificacionSaliente
        SET idEstado         = @idEstadoPendiente,
            intentos         = 0,
            proximoIntentoEn = SYSUTCDATETIME(),
            reservadoHasta   = NULL,
            reservadoPor     = NULL,
            codigoError      = NULL,
            detalleError     = NULL
        WHERE id = @idNotificacion;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_007',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reintentar_notificacion_saliente]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Fachada publica para que el Administrador reencole una notificacion fallida.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_reintentar_notificacion_saliente]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @idNotificacion    UNIQUEIDENTIFIER = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idNotificacionEfectivo   UNIQUEIDENTIFIER = COALESCE(@idNotificacion, @id);
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar idUsuarioEjecutor obligatorio
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar perfil RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar idNotificacion no nulo
        IF @estadoResultado = 1 AND @idNotificacionEfectivo IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' idNotificacion no puede ser nulo. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 5. Reintento atomico delegado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_reintentar_notificacion_saliente_interno
                @idNotificacion = @idNotificacionEfectivo,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- permisos
GO
IF OBJECT_ID(N'dbo.usp_consultar_plantilla_notificacion_activa', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plantilla_notificacion_activa] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_plantillas_notificacion_admin', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plantillas_notificacion_admin] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_guardar_plantilla_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_guardar_plantilla_notificacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_activar_version_plantilla_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_activar_version_plantilla_notificacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_notificacion_saliente_admin', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_notificacion_saliente_admin] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_notificaciones_salientes_admin', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_notificaciones_salientes_admin] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_reintentar_notificacion_saliente', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_reintentar_notificacion_saliente] TO [rol_asistencias_runtime];
GO
