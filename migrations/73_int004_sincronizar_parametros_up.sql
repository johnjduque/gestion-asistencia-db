-- ============================================================================
-- MIGRACION UP 73: INT-004 sincronizacion de parametros desde el Catalogo de Parametros externo (M2M + eventos Pulsar).
--   1. Tabla dbo.SincronizacionParametroExterno (bitacora, idempotencia por idEvento y "el ultimo evento gana") con sus indices y FK.
--   2. Mensajes PRM_013..PRM_016 (los mismos de schema/seed/75_int004_mensajes_parametros_externos.sql).
--   3. Permiso EXECUTE de rol_asistencias_runtime sobre usp_sincronizar_parametro_catalogo_externo (si ya existe).
--   Los SP usp_sincronizar_parametro_catalogo_externo y usp_validar_valor_parametro_externo_interno se despliegan con deploy_schema.ps1
--   (CREATE OR ALTER). Idempotente. Down: 73_int004_sincronizar_parametros_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 73 UP: INT-004 sincronizacion de parametros';
GO

IF OBJECT_ID('dbo.[SincronizacionParametroExterno]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SincronizacionParametroExterno (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_SincronizacionParametroExterno PRIMARY KEY CLUSTERED,
        idEvento           VARCHAR(100)     NULL,
        parametro          UNIQUEIDENTIFIER NULL,
        grupo              VARCHAR(100)     NOT NULL,
        clave              VARCHAR(100)     NOT NULL,
        operacion          VARCHAR(10)      NOT NULL,
        resultado          VARCHAR(20)      NOT NULL,
        valorAnterior      NVARCHAR(4000)   NULL,
        valorNuevo         NVARCHAR(4000)   NULL,
        ocurridoEnUtc      DATETIME2(7)     NOT NULL,
        idCorrelacion      UNIQUEIDENTIFIER NOT NULL,
        fechaRegistroUtc   DATETIME2(7)     NOT NULL CONSTRAINT DF_SincronizacionParametroExterno_fecha DEFAULT SYSUTCDATETIME()
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SincronizacionParametroExterno') AND name = 'UX_SincronizacionParametroExterno_Evento')
    CREATE UNIQUE NONCLUSTERED INDEX UX_SincronizacionParametroExterno_Evento
    ON dbo.SincronizacionParametroExterno (idEvento) WHERE idEvento IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SincronizacionParametroExterno') AND name = 'IX_SincronizacionParametroExterno_Parametro_Ocurrido')
    CREATE NONCLUSTERED INDEX IX_SincronizacionParametroExterno_Parametro_Ocurrido
    ON dbo.SincronizacionParametroExterno (parametro, ocurridoEnUtc DESC) INCLUDE (resultado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SincronizacionParametroExterno_CatalogoParametro')
    ALTER TABLE [dbo].[SincronizacionParametroExterno] ADD CONSTRAINT [FK_SincronizacionParametroExterno_CatalogoParametro] FOREIGN KEY ([parametro]) REFERENCES [dbo].[CatalogoParametro] ([id]);
GO

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

IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_parametro_catalogo_externo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_sincronizar_parametro_catalogo_externo] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 73 UP OK';
GO
