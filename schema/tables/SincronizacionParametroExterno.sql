USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INT-004 (migracion 73): bitacora de la sincronizacion de valores de dbo.CatalogoParametro desde el Catalogo de Parametros externo
-- (M2M + eventos Pulsar). La escribe solo usp_sincronizar_parametro_catalogo_externo, en la misma transaccion que el UPDATE del valor.
-- Sirve a tres fines: (1) idempotencia (idEvento unico: un evento repetido no se vuelve a aplicar), (2) "el ultimo evento gana"
-- (se compara ocurridoEnUtc contra el mayor aplicado del parametro) y (3) auditoria del valor anterior y nuevo. No toca la forma de
-- nueve columnas de CatalogoParametro (DB_BASELINE_CONTRACT). parametro es NULL cuando la clave no existe en la BD (resultado DESCONOCIDO).
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
