USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: mensajes, parametros y plantilla de correo de la recuperacion de contrasena (idempotente).
-- RCL_001 se responde siempre al pedir el enlace, exista o no la cuenta, para no revelar quien esta registrado.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Destino
USING (VALUES
    ('RCL_001', 'SUCCESS',        'BAJO',  N'Si el correo está registrado, recibirá un enlace para definir una contraseña nueva.'),
    ('RCL_002', 'BUSINESS_ERROR', 'MEDIO', N'El enlace para definir la contraseña no es válido o ya venció. Solicite uno nuevo.'),
    ('RCL_003', 'SUCCESS',        'BAJO',  N'Su contraseña fue actualizada. Ya puede iniciar sesión.')
) AS Origen (codigo, tipoMensaje, severidad, contenido)
ON (Destino.codigo = Origen.codigo)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoMensaje = Origen.tipoMensaje, Destino.severidad = Origen.severidad, Destino.contenido = Origen.contenido, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.codigo, Origen.tipoMensaje, Origen.severidad, Origen.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Destino
USING (VALUES
    ('RCL_001', 'SUCCESS',        'BAJO',  N'Solicitud de recuperación recibida; la respuesta no indica si el correo existe.'),
    ('RCL_002', 'BUSINESS_ERROR', 'MEDIO', N'Enlace de recuperación inexistente, vencido, usado, revocado o de usuario inactivo.'),
    ('RCL_003', 'SUCCESS',        'BAJO',  N'Enlace de recuperación consumido (TokenRecuperacionClave.fechaUsoUtc).')
) AS Origen (codigo, tipoMensaje, severidad, contenido)
ON (Destino.codigo = Origen.codigo)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoMensaje = Origen.tipoMensaje, Destino.severidad = Origen.severidad, Destino.contenido = Origen.contenido, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.codigo, Origen.tipoMensaje, Origen.severidad, Origen.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Vigencia del enlace y espera minima entre dos enlaces para el mismo usuario.
MERGE INTO [dbo].[CatalogoParametro] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'TTL_MINUTOS', N'60', 'INT', N'60'),
    ('RECUPERACION_CLAVE', 'REENVIO_ESPERA_MINUTOS', N'5', 'INT', N'5')
) AS Origen (grupo, clave, valor, tipoDato, valorDefecto)
ON (Destino.grupo = Origen.grupo AND Destino.clave = Origen.clave)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoDato = Origen.tipoDato, Destino.valorDefecto = Origen.valorDefecto, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.grupo, Origen.clave, Origen.valor, Origen.tipoDato, Origen.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Plantilla v1 del correo. El marcador {enlace} lo resuelve el canal de correo al entregar; nunca se guarda en el outbox.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'nombre', N'Primer nombre del usuario', N'Juan', 1),
    ('RECUPERACION_CLAVE', 'enlace', N'Enlace de un solo uso para definir la contraseña (lo genera el sistema al enviar)', N'https://plataforma/restablecer-clave#token=...', 1)
) AS Origen (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Destino.tipo = Origen.tipo AND Destino.marcador = Origen.marcador)
WHEN MATCHED THEN
    UPDATE SET Destino.descripcion = Origen.descripcion, Destino.ejemplo = Origen.ejemplo, Destino.obligatorio = Origen.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Origen.tipo, Origen.marcador, Origen.descripcion, Origen.ejemplo, Origen.obligatorio);
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'es', 1,
     N'Defina una contraseña nueva',
     N'Hola {nombre}, recibimos una solicitud para definir una contraseña nueva de su cuenta en la plataforma de asistencia. Abra el siguiente enlace para hacerlo: {enlace} . El enlace es de un solo uso y vence pronto. Si usted no hizo esta solicitud, ignore este mensaje: su contraseña actual sigue funcionando.',
     1)
) AS Origen (tipo, idioma, version, asunto, cuerpo, activa)
ON (Destino.tipo = Origen.tipo AND Destino.idioma = Origen.idioma AND Destino.version = Origen.version)
WHEN MATCHED THEN
    UPDATE SET Destino.asunto = Origen.asunto, Destino.cuerpo = Origen.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Origen.tipo, Origen.idioma, Origen.version, Origen.asunto, Origen.cuerpo, Origen.activa, NULL, SYSUTCDATETIME());
GO
