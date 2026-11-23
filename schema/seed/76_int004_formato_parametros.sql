USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INT-004 (migracion 74): formato declarativo de los parametros que traen listas de rangos de red, y su mensaje de rechazo. Idempotente.
--   PRM_017  el valor no es una lista de rangos CIDR validos (RED/CIDRS_CAMPUS y RED/PROXIES_CONFIABLES, formato CIDR_LIST)
-- Las dos filas de CatalogoParametroEdicion son NO editables (esEditable = 0, el grupo RED es protegido): solo declaran el formato para que
-- usp_validar_valor_parametro_externo_interno rechace un valor invalido que llegue del Catalogo de Parametros externo.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PRM_017', 'VALIDATION_ERROR', 'BAJO', N'El valor debe ser una lista de rangos de red válidos separados por comas (por ejemplo 10.0.0.0/8,192.168.0.0/16).')
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
    ('PRM_017', 'VALIDATION_ERROR', 'BAJO', N'ufn_validar_formato_valor: el valor no cumple CatalogoParametroEdicion.formato = CIDR_LIST (cada elemento separado por comas debe ser IPv4 a.b.c.d/0-32 o IPv6 con prefijo 0-128).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
USING (
    SELECT p.id AS parametro, v.etiqueta, v.descripcion, v.categoriaVisual, v.orden, v.formato
    FROM (VALUES
        ('RED', 'CIDRS_CAMPUS',       N'Rangos de red del campus', N'Lista de rangos CIDR separados por comas desde los que se acepta el registro de asistencia por QR o PIN.', N'Red', CONVERT(SMALLINT, 10), 'CIDR_LIST'),
        ('RED', 'PROXIES_CONFIABLES', N'Proxies confiables',       N'Lista de rangos CIDR de los proxies cuyo X-Forwarded-For se acepta para resolver la IP del cliente.',       N'Red', CONVERT(SMALLINT, 20), 'CIDR_LIST')
    ) AS v (grupo, clave, etiqueta, descripcion, categoriaVisual, orden, formato)
    INNER JOIN dbo.CatalogoParametro p ON p.grupo = v.grupo AND p.clave = v.clave
) AS Source
ON (Target.parametro = Source.parametro)
WHEN MATCHED THEN
    UPDATE SET Target.formato = Source.formato
WHEN NOT MATCHED THEN
    INSERT (parametro, esEditable, etiqueta, descripcion, categoriaVisual, orden, formato)
    VALUES (Source.parametro, 0, Source.etiqueta, Source.descripcion, Source.categoriaVisual, Source.orden, Source.formato);
GO
