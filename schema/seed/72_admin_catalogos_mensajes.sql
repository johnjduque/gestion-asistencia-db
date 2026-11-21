USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Migracion 65: administracion de los catalogos de categorias de justificacion y de motivos de cancelacion de sesion (ADMINISTRADOR).
--   CTG_001 nombre invalido, CTG_002 codigo invalido, CTG_003 no se desactiva el ultimo activo, CTG_004 descripcion invalida,
--   CTG_005 registro inexistente, CTG_006 codigo o nombre repetido, CTG_007 guardado, CTG_008 cambio de estado.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('CTG_001', 'VALIDATION_ERROR', 'BAJO',  N'El campo {} es obligatorio, admite hasta {} caracteres y solo letras, números, espacios y los signos . , - _ ( ) / # :.'),
    ('CTG_002', 'VALIDATION_ERROR', 'BAJO',  N'El código es obligatorio, admite hasta {} caracteres y solo letras mayúsculas, números y guion bajo (_).'),
    ('CTG_003', 'BUSINESS_ERROR',   'MEDIO', N'No se puede desactivar el último registro activo del catálogo de {}: debe quedar al menos uno disponible.'),
    ('CTG_004', 'VALIDATION_ERROR', 'BAJO',  N'La descripción admite hasta {} caracteres y no puede contener los símbolos < ni >.'),
    ('CTG_005', 'BUSINESS_ERROR',   'MEDIO', N'El registro indicado del catálogo de {} no existe.'),
    ('CTG_006', 'BUSINESS_ERROR',   'MEDIO', N'Ya existe un registro del catálogo de {} con el mismo {}.'),
    ('CTG_007', 'SUCCESS',          'BAJO',  N'El registro del catálogo de {} quedó guardado.'),
    ('CTG_008', 'SUCCESS',          'BAJO',  N'El registro del catálogo de {} quedó {}.')
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
    ('CTG_001', 'VALIDATION_ERROR', 'BAJO',  N'Regla ADM-CAT: el campo [{}] llegó vacío, supera {} caracteres o trae caracteres fuera de letras, números, espacio y . , - _ ( ) / # :.'),
    ('CTG_002', 'VALIDATION_ERROR', 'BAJO',  N'Regla ADM-CAT: @codigo vacío, mayor de {} caracteres o con caracteres fuera de [A-Z0-9_].'),
    ('CTG_003', 'BUSINESS_ERROR',   'MEDIO', N'Regla ADM-CAT: se intentó desactivar el último registro activo del catálogo [{}].'),
    ('CTG_004', 'VALIDATION_ERROR', 'BAJO',  N'Regla ADM-CAT: @descripcion supera {} caracteres o contiene < o >.'),
    ('CTG_005', 'BUSINESS_ERROR',   'MEDIO', N'Regla ADM-CAT: no existe el registro solicitado en el catálogo [{}].'),
    ('CTG_006', 'BUSINESS_ERROR',   'MEDIO', N'Regla ADM-CAT: duplicado de [{}] en el catálogo [{}] (índice único).'),
    ('CTG_007', 'SUCCESS',          'BAJO',  N'Catálogo [{}]: registro creado o actualizado por el ADMINISTRADOR.'),
    ('CTG_008', 'SUCCESS',          'BAJO',  N'Catálogo [{}]: estaActivo cambiado por el ADMINISTRADOR (sin borrado físico).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
