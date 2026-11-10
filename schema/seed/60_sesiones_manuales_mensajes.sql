USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: mensajes de la cancelacion de una sesion manual por el coordinador. Idempotente (MERGE por codigo).
--   SES_018 la sesion no fue creada manualmente por el docente (409).
--   SES_019 el motivo no existe en el catalogo (400).
--   SES_020 la sesion fue cancelada por la coordinacion (exito).
--   SES_021 la observacion supera el maximo parametrizado (400).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_018', 'BUSINESS_ERROR',   'MEDIO', N'Solo las sesiones creadas manualmente por el docente pueden ser canceladas por el coordinador.'),
    ('SES_019', 'VALIDATION_ERROR', 'BAJO',  N'El motivo de cancelación no es válido.'),
    ('SES_020', 'SUCCESS',          'BAJO',  N'La sesión fue cancelada por la coordinación del programa.'),
    ('SES_021', 'VALIDATION_ERROR', 'BAJO',  N'La observación no puede superar {} caracteres.')
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
    ('SES_018', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la sesión [{}] no es manual (procedencia UTC_GENERADOR o UTC_OWNER); el coordinador no puede cancelarla; sin escrituras.'),
    ('SES_019', 'VALIDATION_ERROR', 'BAJO',  N'Validación: codigoMotivo [{}] ausente o fuera de MotivoCancelacionSesion activo; sin escrituras.'),
    ('SES_020', 'SUCCESS',          'BAJO',  N'Sesión [{}] cancelada por el coordinador; tipo [{}].'),
    ('SES_021', 'VALIDATION_ERROR', 'BAJO',  N'Validación: la observación recortada supera SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA ({}); sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- CULM-001 / DEC-065 (2): mensajes de la solicitud de sesion extraordinaria con aval del coordinador. Idempotente (MERGE por codigo).
--   SES_022 la sesion quedo registrada como solicitud pendiente (exito de la creacion por el docente).
--   SES_023 la sesion esta pendiente de aprobacion: no admite tomas ni asistencia (409).
--   SES_024 la solicitud ya fue resuelta (409).
--   SES_025 la sesion no tiene solicitud de aprobacion (409).
--   SES_026 la solicitud fue aprobada (exito).
--   SES_027 la solicitud fue rechazada y la sesion cancelada (exito).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_022', 'SUCCESS',        'BAJO',  N'La sesión extraordinaria quedó registrada como solicitud pendiente de aprobación del coordinador del programa.'),
    ('SES_023', 'BUSINESS_ERROR', 'MEDIO', N'La sesión está pendiente de aprobación del coordinador.'),
    ('SES_024', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud ya fue resuelta.'),
    ('SES_025', 'BUSINESS_ERROR', 'MEDIO', N'La sesión no tiene una solicitud de aprobación.'),
    ('SES_026', 'SUCCESS',        'BAJO',  N'La solicitud de sesión extraordinaria fue aprobada.'),
    ('SES_027', 'SUCCESS',        'BAJO',  N'La solicitud de sesión extraordinaria fue rechazada y la sesión quedó cancelada.')
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
    ('SES_022', 'SUCCESS',        'BAJO',  N'Sesión [{}] creada por el docente con solicitud PENDIENTE de aprobación del coordinador.'),
    ('SES_023', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesión [{}] tiene una solicitud en espera (EstadoSolicitudSesion.esFinal = 0); no admite tomas ni asistencia; sin escrituras.'),
    ('SES_024', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud de la sesión [{}] ya está en un estado final (aprobada o rechazada); sin escrituras.'),
    ('SES_025', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesión [{}] no tiene fila en SesionSolicitud (generada o anterior a DEC-065); sin escrituras.'),
    ('SES_026', 'SUCCESS',        'BAJO',  N'Solicitud de la sesión [{}] aprobada por el coordinador.'),
    ('SES_027', 'SUCCESS',        'BAJO',  N'Solicitud de la sesión [{}] rechazada por el coordinador; la sesión quedó cancelada (tipo manual).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
