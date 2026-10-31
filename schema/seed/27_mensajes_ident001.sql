USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: mensajes de catalogo del correo institucional y la verificacion del correo (usuario y tecnicos).
-- El marcador {} se reemplaza por el parametro recibido (dominio institucional en VCE_001).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('VCE_001', 'BUSINESS_ERROR', 'MEDIO', N'El correo del estudiante debe ser institucional y terminar en {}.'),
    ('VCE_002', 'BUSINESS_ERROR', 'MEDIO', N'El enlace de verificación no es válido o ya venció.'),
    ('VCE_003', 'BUSINESS_ERROR', 'BAJO',  N'Debe esperar unos minutos antes de volver a enviar el enlace de verificación.'),
    ('VCE_004', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante no pertenece a un grupo a su cargo.'),
    ('VCE_005', 'BUSINESS_ERROR', 'BAJO',  N'El correo de este estudiante ya fue verificado.'),
    ('VCE_006', 'SUCCESS',        'BAJO',  N'Su correo fue verificado. Ya puede iniciar sesión.'),
    ('VCE_007', 'BUSINESS_ERROR', 'MEDIO', N'El usuario no existe o no está activo.')
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
    ('VCE_001', 'BUSINESS_ERROR', 'MEDIO', N'Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}).'),
    ('VCE_002', 'BUSINESS_ERROR', 'MEDIO', N'Token de verificación inexistente, vencido, usado, revocado o de usuario inactivo.'),
    ('VCE_003', 'BUSINESS_ERROR', 'BAJO',  N'Regla: aún no transcurre VERIFICACION_CORREO/REENVIO_ESPERA_MINUTOS desde la última emisión.'),
    ('VCE_004', 'BUSINESS_ERROR', 'MEDIO', N'Ámbito: el ejecutor no es titular del grupo ni coordinador de su programa, o el estudiante no pertenece al grupo.'),
    ('VCE_005', 'BUSINESS_ERROR', 'BAJO',  N'Estado: Usuario.correoConfirmado ya es 1.'),
    ('VCE_006', 'SUCCESS',        'BAJO',  N'Token consumido y Usuario.correoConfirmado = 1.'),
    ('VCE_007', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.Usuario activo con el id indicado.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
