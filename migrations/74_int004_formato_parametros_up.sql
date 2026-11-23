-- ============================================================================
-- MIGRACION UP 74: INT-004 formato declarativo de parametros (RED/CIDRS_CAMPUS y RED/PROXIES_CONFIABLES) validado al sincronizar.
--   1. Columna dbo.CatalogoParametroEdicion.formato (VARCHAR(20) NULL) y CK_CPE_Formato (CIDR_LIST).
--   2. Mensaje PRM_017 (el mismo de schema/seed/76_int004_formato_parametros.sql).
--   3. Filas NO editables de CatalogoParametroEdicion para RED/CIDRS_CAMPUS y RED/PROXIES_CONFIABLES con formato CIDR_LIST (si el parametro existe).
--   Las funciones ufn_es_cidr_valido y ufn_validar_formato_valor y los SP usp_validar_valor_parametro_externo_interno y usp_actualizar_parametro
--   se despliegan con deploy_schema.ps1 (CREATE OR ALTER). Idempotente. Down: 74_int004_formato_parametros_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 74 UP: INT-004 formato de parametros';
GO

IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NULL
    ALTER TABLE [dbo].[CatalogoParametroEdicion] ADD [formato] VARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CPE_Formato' AND parent_object_id = OBJECT_ID('dbo.CatalogoParametroEdicion'))
    ALTER TABLE [dbo].[CatalogoParametroEdicion] ADD CONSTRAINT [CK_CPE_Formato] CHECK ([formato] IS NULL OR [formato] IN ('CIDR_LIST'));
GO

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

-- Lote propio: la columna formato se crea arriba y este lote la referencia (compila despues de crearla)
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
PRINT 'MIGRACION 74 UP OK';
GO
