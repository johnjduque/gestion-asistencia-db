USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
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
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('VCE_009', 'BUSINESS_ERROR', 'BAJO',  N'Defina su contraseña para activar su cuenta.'),
    ('ACT_001', 'SUCCESS',        'BAJO',  N'Se envió de nuevo el enlace de activación al correo institucional.'),
    ('ACT_002', 'BUSINESS_ERROR', 'BAJO',  N'La cuenta ya está activa; no es necesario enviar el enlace de activación.')
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
    ('VCE_009', 'BUSINESS_ERROR', 'BAJO',  N'Regla: la cuenta del proveedor de identidad no tiene credencial y la activación no incluyó contraseña; el token no se consumió.'),
    ('ACT_001', 'SUCCESS',        'BAJO',  N'Aviso ACTIVACION_CUENTA registrado en el outbox para el usuario indicado.'),
    ('ACT_002', 'BUSINESS_ERROR', 'BAJO',  N'Estado: Usuario.correoConfirmado ya es 1 (cuenta activada).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
