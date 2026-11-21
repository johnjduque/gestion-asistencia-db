USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2, semilla 52 = 50 + 2; DEC-044 (1)): varios soportes por reclamo, categoria persistida y soporte
-- obligatorio. Idempotente (MERGE por clave natural); los parametros no pisan `valor` si el administrador ya lo cambio.
--   ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO  tope de soportes de un reclamo (3)
--   ARCHIVO/ESTADO_BORRADOR               estado DRAFT del soporte recien subido (TD-061: sin literal quemado en los SP)
--   ARCHIVO/TIPOS_PERMITIDOS              tipos de contenido que acepta la subida (coincide con CK_ArchivoSoporte_TipoContenido)
-- La fila de edicion de MAXIMO_SOPORTES_POR_RECLAMO ([1, 10]) en CatalogoParametroEdicion la siembra 53_culm001_d3_parametro_edicion.sql
-- (corre despues de esta semilla, con el parametro ya creado); la prueba D2 la verifica.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO', N'3',                                  'INT',    N'3'),
    ('ARCHIVO',  'ESTADO_BORRADOR',             N'DRAFT',                              'STRING', N'DRAFT'),
    ('ARCHIVO',  'TIPOS_PERMITIDOS',            N'application/pdf,image/png,image/jpeg', 'STRING', N'application/pdf,image/png,image/jpeg')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- HU014/HU015: soporte obligatorio por categoria (MED, ACA y LAB). La columna requiereSoporte la crea CategoriaJustificacion.sql.
IF COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NOT NULL
    EXEC sys.sp_executesql N'
        MERGE INTO [dbo].[CategoriaJustificacion] AS Target
        USING (VALUES (N''MED'', 1), (N''CAL'', 0), (N''ACA'', 1), (N''FMA'', 0), (N''LAB'', 1), (N''OTR'', 0)) AS Source (codigo, requiereSoporte)
        ON (Target.codigo = Source.codigo)
        WHEN MATCHED AND Target.requiereSoporte <> Source.requiereSoporte THEN
            UPDATE SET Target.requiereSoporte = Source.requiereSoporte;';
GO

-- Mensajes REV_021..REV_024 (radicacion con categoria y soportes multiples). Idempotente (MERGE por codigo).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REV_021', 'BUSINESS_ERROR', 'MEDIO', N'La categoría de justificación no es válida.'),
    ('REV_022', 'BUSINESS_ERROR', 'MEDIO', N'La categoría «{}» exige adjuntar al menos un soporte.'),
    ('REV_023', 'BUSINESS_ERROR', 'MEDIO', N'Puedes adjuntar como máximo {} soportes.'),
    ('REV_024', 'BUSINESS_ERROR', 'MEDIO', N'Un mismo soporte no se puede adjuntar dos veces.')
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
    ('REV_021', 'BUSINESS_ERROR', 'MEDIO', N'HU015: la categoría [{}] no existe en CategoriaJustificacion (ni por código ni por nombre).'),
    ('REV_022', 'BUSINESS_ERROR', 'MEDIO', N'HU014: la categoría [{}] tiene requiereSoporte = 1 y la solicitud llegó sin soportes.'),
    ('REV_023', 'BUSINESS_ERROR', 'MEDIO', N'HU015: [{}] soportes superan ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO = [{}].'),
    ('REV_024', 'BUSINESS_ERROR', 'MEDIO', N'HU015: la lista de soportes repite al menos un idArchivoSoporte.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
