USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
