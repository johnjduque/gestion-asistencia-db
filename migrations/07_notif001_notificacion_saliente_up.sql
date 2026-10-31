USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP: NOTIF-001 - Capacidad de notificaciones outbox
-- ============================================================================

-- 1. Tabla catalogo: EstadoNotificacion
IF OBJECT_ID('dbo.EstadoNotificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoNotificacion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     VARCHAR(30)      NOT NULL,
        nombre     NVARCHAR(60)     NOT NULL,
        esTerminal BIT              NOT NULL,
        CONSTRAINT PK_EstadoNotificacion PRIMARY KEY CLUSTERED (id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_EstadoNotificacion_codigo' AND object_id = OBJECT_ID('dbo.EstadoNotificacion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_EstadoNotificacion_codigo ON dbo.EstadoNotificacion (codigo);
END
GO

-- Semilla EstadoNotificacion
MERGE INTO [dbo].[EstadoNotificacion] AS Target
USING (VALUES
    ('PENDIENTE', 'Pendiente', 0),
    ('RESERVADA', 'Reservada', 0),
    ('FALLIDA_REINTENTABLE', 'Fallida reintentable', 0),
    ('ENTREGADA', 'Entregada', 1),
    ('FALLIDA_DEFINITIVA', 'Fallida definitiva', 1)
) AS Source (codigo, nombre, esTerminal)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.esTerminal = Source.esTerminal
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, esTerminal)
    VALUES (NEWID(), Source.codigo, Source.nombre, Source.esTerminal);
GO

-- 2. Tabla transaccional: NotificacionSaliente
IF OBJECT_ID('dbo.NotificacionSaliente', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.NotificacionSaliente (
        id                UNIQUEIDENTIFIER    NOT NULL,
        tipo              VARCHAR(60)         NOT NULL,
        asunto            NVARCHAR(200)       NULL,
        mensaje           NVARCHAR(4000)      NULL,
        destinatarios     NVARCHAR(MAX)       NOT NULL,
        datos             NVARCHAR(MAX)       NOT NULL CONSTRAINT DF_NotificacionSaliente_datos DEFAULT '{}',
        idEstado          UNIQUEIDENTIFIER    NOT NULL,
        intentos          INT                 NOT NULL CONSTRAINT DF_NotificacionSaliente_intentos DEFAULT 0,
        creadoEn          DATETIMEOFFSET(7)   NOT NULL,
        proximoIntentoEn  DATETIMEOFFSET(7)   NULL,
        reservadoHasta    DATETIMEOFFSET(7)   NULL,
        reservadoPor      NVARCHAR(100)       NULL,
        entregadoEn       DATETIMEOFFSET(7)   NULL,
        codigoError       VARCHAR(40)         NULL,
        detalleError      NVARCHAR(300)       NULL,
        idCorrelacion     UNIQUEIDENTIFIER    NULL,
        traceId           CHAR(32)            NULL,
        spanId            CHAR(16)            NULL,
        CONSTRAINT PK_NotificacionSaliente PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_NotificacionSaliente_destinatarios_json CHECK (ISJSON(destinatarios) = 1),
        CONSTRAINT CK_NotificacionSaliente_datos_json CHECK (ISJSON(datos) = 1),
        CONSTRAINT FK_NotificacionSaliente_Estado FOREIGN KEY (idEstado) REFERENCES dbo.EstadoNotificacion(id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_NotificacionSaliente_despacho' AND object_id = OBJECT_ID('dbo.NotificacionSaliente'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_NotificacionSaliente_despacho
    ON dbo.NotificacionSaliente (idEstado, proximoIntentoEn, creadoEn)
    INCLUDE (reservadoHasta);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_NotificacionSaliente_retencion' AND object_id = OBJECT_ID('dbo.NotificacionSaliente'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_NotificacionSaliente_retencion
    ON dbo.NotificacionSaliente (idEstado, creadoEn);
END
GO
