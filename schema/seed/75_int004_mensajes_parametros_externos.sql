USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INT-004 (migracion 73): mensajes de usp_sincronizar_parametro_catalogo_externo. Idempotente (MERGE por codigo).
--   PRM_013  valor aplicado desde el Catalogo de Parametros externo
--   PRM_014  evento ya procesado (idempotencia por eventId)
--   PRM_015  evento mas antiguo que el ultimo aplicado ("el ultimo evento gana")
--   PRM_016  la clave no existe en la BD (no se crean filas)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PRM_013', 'SUCCESS',  'BAJO', N'Parámetro sincronizado desde el catálogo externo.'),
    ('PRM_014', 'SUCCESS',  'BAJO', N'El evento ya había sido procesado.'),
    ('PRM_015', 'SUCCESS',  'BAJO', N'Se ignoró un evento más antiguo que el último aplicado.'),
    ('PRM_016', 'SUCCESS',  'BAJO', N'El parámetro no existe en este sistema; se ignoró.')
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
    ('PRM_013', 'SUCCESS', 'BAJO', N'usp_sincronizar_parametro_catalogo_externo: CatalogoParametro.valor actualizado (UPSERT) o devuelto a valorDefecto (DELETE) y registrado en SincronizacionParametroExterno.'),
    ('PRM_014', 'SUCCESS', 'BAJO', N'usp_sincronizar_parametro_catalogo_externo: el idEvento ya existe en SincronizacionParametroExterno; no se escribio nada.'),
    ('PRM_015', 'SUCCESS', 'BAJO', N'usp_sincronizar_parametro_catalogo_externo: ocurridoEnUtc es menor que el ultimo valor aplicado del parametro; no se escribio el valor.'),
    ('PRM_016', 'SUCCESS', 'BAJO', N'usp_sincronizar_parametro_catalogo_externo: no hay un CatalogoParametro activo con ese grupo y clave; no se crean filas.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
