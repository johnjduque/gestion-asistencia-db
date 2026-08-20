USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[AuditoriaEvento]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[AuditoriaEvento] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [occurredAt] DATETIMEOFFSET(7) NOT NULL,
    [actorId] NVARCHAR(120) NULL,
    [actorType] VARCHAR(20) NOT NULL,
    [action] VARCHAR(120) NOT NULL,
    [resourceType] VARCHAR(120) NOT NULL,
    [resourceId] NVARCHAR(120) NULL,
    [result] VARCHAR(20) NOT NULL,
    [correlationId] UNIQUEIDENTIFIER NULL,
    [traceId] CHAR(32) NULL,
    [spanId] CHAR(16) NULL,
    [httpMethod] VARCHAR(16) NOT NULL,
    [path] NVARCHAR(240) NOT NULL,
    [httpStatus] SMALLINT NOT NULL,
    [clientIp] VARCHAR(45) NULL,
    [errorCode] VARCHAR(120) NULL,
    [metadata] NVARCHAR(MAX) NULL,
    CONSTRAINT [PK_AuditoriaEvento] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [CK_AuditoriaEvento_ActorType] CHECK ([actorType] IN ('USER', 'ANONYMOUS', 'SYSTEM')),
    CONSTRAINT [CK_AuditoriaEvento_Result] CHECK ([result] IN ('SUCCESS', 'FAILURE')),
    CONSTRAINT [CK_AuditoriaEvento_HttpStatus] CHECK ([httpStatus] >= 100 AND [httpStatus] <= 599),
    CONSTRAINT [CK_AuditoriaEvento_MetadataJson] CHECK ([metadata] IS NULL OR ISJSON([metadata]) = 1)
);
END
GO

IF OBJECT_ID('dbo.[AuditoriaEvento]', 'U') IS NOT NULL
BEGIN
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
      AND [name] COLLATE Latin1_General_BIN2 IN (
          N'IX_AuditoriaEvento_occurredAt',
          N'IX_AuditoriaEvento_correlationId',
          N'IX_AuditoriaEvento_traceId'
      )
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
          AND [name] COLLATE Latin1_General_BIN2 = N'IX_AuditoriaEvento_occurredAt'
    )
    BEGIN
        DROP INDEX [IX_AuditoriaEvento_occurredAt] ON [dbo].[AuditoriaEvento];
    END

    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
          AND [name] COLLATE Latin1_General_BIN2 = N'IX_AuditoriaEvento_correlationId'
    )
    BEGIN
        DROP INDEX [IX_AuditoriaEvento_correlationId] ON [dbo].[AuditoriaEvento];
    END

    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
          AND [name] COLLATE Latin1_General_BIN2 = N'IX_AuditoriaEvento_traceId'
    )
    BEGIN
        DROP INDEX [IX_AuditoriaEvento_traceId] ON [dbo].[AuditoriaEvento];
    END
END

IF EXISTS (
    SELECT 1
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.[object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
      AND (
          (c.[name] = N'id' AND t.[name] <> N'uniqueidentifier')
          OR (c.[name] = N'occurredAt' AND (t.[name] <> N'datetimeoffset' OR c.[scale] <> 7))
          OR (c.[name] = N'actorId' AND (t.[name] <> N'nvarchar' OR c.[max_length] <> 240 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'actorType' AND (t.[name] <> N'varchar' OR c.[max_length] <> 20 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'action' AND (t.[name] <> N'varchar' OR c.[max_length] <> 120 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'resourceType' AND (t.[name] <> N'varchar' OR c.[max_length] <> 120 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'resourceId' AND (t.[name] <> N'nvarchar' OR c.[max_length] <> 240 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'result' AND (t.[name] <> N'varchar' OR c.[max_length] <> 20 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'correlationId' AND (t.[name] <> N'uniqueidentifier' OR c.[is_nullable] <> 1))
          OR (c.[name] = N'traceId' AND (t.[name] <> N'char' OR c.[max_length] <> 32 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'spanId' AND (t.[name] <> N'char' OR c.[max_length] <> 16 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'httpMethod' AND (t.[name] <> N'varchar' OR c.[max_length] <> 16 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'path' AND (t.[name] <> N'nvarchar' OR c.[max_length] <> 480 OR c.[is_nullable] <> 0))
          OR (c.[name] = N'httpStatus' AND (t.[name] <> N'smallint' OR c.[is_nullable] <> 0))
          OR (c.[name] = N'clientIp' AND (t.[name] <> N'varchar' OR c.[max_length] <> 45 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'errorCode' AND (t.[name] <> N'varchar' OR c.[max_length] <> 120 OR c.[is_nullable] <> 1))
          OR (c.[name] = N'metadata' AND (t.[name] <> N'nvarchar' OR c.[max_length] <> -1 OR c.[is_nullable] <> 1))
      )
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
          AND [name] IN (
              N'IX_AuditoriaEvento_OccurredAt',
              N'IX_AuditoriaEvento_CorrelationId_OccurredAt',
              N'IX_AuditoriaEvento_TraceId_OccurredAt',
              N'IX_AuditoriaEvento_ActorId_OccurredAt',
              N'IX_AuditoriaEvento_Action_OccurredAt',
              N'IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt'
          )
    )
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_OccurredAt] ON [dbo].[AuditoriaEvento];
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_CorrelationId_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_CorrelationId_OccurredAt] ON [dbo].[AuditoriaEvento];
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_TraceId_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_TraceId_OccurredAt] ON [dbo].[AuditoriaEvento];
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ActorId_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_ActorId_OccurredAt] ON [dbo].[AuditoriaEvento];
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_Action_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_Action_OccurredAt] ON [dbo].[AuditoriaEvento];
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt')
            DROP INDEX [IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt] ON [dbo].[AuditoriaEvento];
    END

    IF EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
          AND [name] = N'PK_AuditoriaEvento'
    )
    BEGIN
        ALTER TABLE [dbo].[AuditoriaEvento] DROP CONSTRAINT [PK_AuditoriaEvento];
    END

    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [id] UNIQUEIDENTIFIER NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [occurredAt] DATETIMEOFFSET(7) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [actorId] NVARCHAR(120) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [actorType] VARCHAR(20) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [action] VARCHAR(120) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [resourceType] VARCHAR(120) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [resourceId] NVARCHAR(120) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [result] VARCHAR(20) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [correlationId] UNIQUEIDENTIFIER NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [traceId] CHAR(32) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [spanId] CHAR(16) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [httpMethod] VARCHAR(16) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [path] NVARCHAR(240) NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [httpStatus] SMALLINT NOT NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [clientIp] VARCHAR(45) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [errorCode] VARCHAR(120) NULL;
    ALTER TABLE [dbo].[AuditoriaEvento] ALTER COLUMN [metadata] NVARCHAR(MAX) NULL;
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.key_constraints
    WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
      AND [name] = N'PK_AuditoriaEvento'
)
BEGIN
    ALTER TABLE [dbo].[AuditoriaEvento] ADD CONSTRAINT [PK_AuditoriaEvento] PRIMARY KEY CLUSTERED ([id]);
END

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'CK_AuditoriaEvento_ActorType')
BEGIN
    ALTER TABLE [dbo].[AuditoriaEvento] WITH CHECK ADD CONSTRAINT [CK_AuditoriaEvento_ActorType] CHECK ([actorType] IN ('USER', 'ANONYMOUS', 'SYSTEM'));
END

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'CK_AuditoriaEvento_Result')
BEGIN
    ALTER TABLE [dbo].[AuditoriaEvento] WITH CHECK ADD CONSTRAINT [CK_AuditoriaEvento_Result] CHECK ([result] IN ('SUCCESS', 'FAILURE'));
END

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'CK_AuditoriaEvento_HttpStatus')
BEGIN
    ALTER TABLE [dbo].[AuditoriaEvento] WITH CHECK ADD CONSTRAINT [CK_AuditoriaEvento_HttpStatus] CHECK ([httpStatus] >= 100 AND [httpStatus] <= 599);
END

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'CK_AuditoriaEvento_MetadataJson')
BEGIN
    ALTER TABLE [dbo].[AuditoriaEvento] WITH CHECK ADD CONSTRAINT [CK_AuditoriaEvento_MetadataJson] CHECK ([metadata] IS NULL OR ISJSON([metadata]) = 1);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_OccurredAt] ON [dbo].[AuditoriaEvento] ([occurredAt]);');
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_CorrelationId_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_CorrelationId_OccurredAt] ON [dbo].[AuditoriaEvento] ([correlationId], [occurredAt]);');
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_TraceId_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_TraceId_OccurredAt] ON [dbo].[AuditoriaEvento] ([traceId], [occurredAt]);');
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ActorId_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_ActorId_OccurredAt] ON [dbo].[AuditoriaEvento] ([actorId], [occurredAt]);');
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_Action_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_Action_OccurredAt] ON [dbo].[AuditoriaEvento] ([action], [occurredAt]);');
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt')
BEGIN
    EXEC(N'CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt] ON [dbo].[AuditoriaEvento] ([resourceType], [resourceId], [occurredAt]);');
END
END
GO
