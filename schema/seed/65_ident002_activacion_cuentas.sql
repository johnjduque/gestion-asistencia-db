USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- IDENT-002: activacion de cuentas registradas por otra persona (sin contrasena en el registro). Mensajes VCE_009, ACT_001 y ACT_002
-- (usuario y tecnicos). Idempotente. La plantilla del aviso ACTIVACION_CUENTA vive desde la migracion 71 en el Servicio de Notificaciones.
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
