USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU074: mensajes del estado de la asignatura (activar / inactivar y su efecto). Idempotente (MERGE por codigo).
--   ASI_009  inactivar con grupos en el periodo vigente o en periodos futuros (usp_toggle_estado_asignatura)
--   ASI_010  asignatura inactiva usada para crear un grupo o asociarla a un plan (usp_validar_asignatura_activa_interno)
--   ASI_011  exito: la asignatura quedo activa
--   ASI_012  exito: la asignatura quedo inactiva
-- Migracion: 57_hu074_estado_asignatura_reglas_up.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ASI_009', 'BUSINESS_ERROR', 'ALTO',  N'No puedes inactivar la asignatura: tiene grupos en el período vigente o en períodos futuros.'),
    ('ASI_010', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura está inactiva; actívala para usarla.'),
    ('ASI_011', 'SUCCESS',        'BAJO',  N'La asignatura quedó activa.'),
    ('ASI_012', 'SUCCESS',        'BAJO',  N'La asignatura quedó inactiva.')
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
    ('ASI_009', 'BUSINESS_ERROR', 'ALTO',  N'Regla HU074: la asignatura tiene grupos en un periodo academico vigente o futuro (uv_periodo_academico.estado distinto de CERRADO); no se inactiva.'),
    ('ASI_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla HU074: Asignatura.estado = 0; no se crean grupos ni se asocia a planes hasta reactivarla.'),
    ('ASI_011', 'SUCCESS',        'BAJO',  N'HU074: Asignatura.estado pasa de 0 a 1.'),
    ('ASI_012', 'SUCCESS',        'BAJO',  N'HU074: Asignatura.estado pasa de 1 a 0.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
