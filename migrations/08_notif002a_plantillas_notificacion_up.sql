USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP: NOTIF-002A - Plantillas de notificacion y catalogo de marcadores
-- ============================================================================

-- 1. Tabla: PlantillaNotificacion
IF OBJECT_ID('dbo.PlantillaNotificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacion (
        id        UNIQUEIDENTIFIER NOT NULL,
        tipo      VARCHAR(60)      NOT NULL,
        idioma    CHAR(2)          NOT NULL CONSTRAINT DF_PlantillaNotificacion_idioma DEFAULT 'es',
        version   INT              NOT NULL,
        asunto    NVARCHAR(200)    NOT NULL,
        cuerpo    NVARCHAR(4000)   NOT NULL,
        activa    BIT              NOT NULL,
        creadoPor UNIQUEIDENTIFIER NULL,
        creadoEn  DATETIME2(3)     NOT NULL,
        CONSTRAINT PK_PlantillaNotificacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacion_tipo_idioma_version UNIQUE (tipo, idioma, version),
        CONSTRAINT CK_PlantillaNotificacion_version CHECK (version >= 1),
        CONSTRAINT CK_PlantillaNotificacion_tipo CHECK (LEN(TRIM(tipo)) BETWEEN 3 AND 60 AND tipo NOT LIKE '%[^A-Z0-9_]%')
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_PlantillaNotificacion_activa' AND object_id = OBJECT_ID('dbo.PlantillaNotificacion'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PlantillaNotificacion_activa
    ON dbo.PlantillaNotificacion (tipo, idioma)
    WHERE activa = 1;
END
GO

-- 2. Tabla catalogo: PlantillaNotificacionMarcador
IF OBJECT_ID('dbo.PlantillaNotificacionMarcador', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlantillaNotificacionMarcador (
        id          UNIQUEIDENTIFIER NOT NULL,
        tipo        VARCHAR(60)      NOT NULL,
        marcador    VARCHAR(40)      NOT NULL,
        descripcion NVARCHAR(200)    NOT NULL,
        ejemplo     NVARCHAR(100)    NOT NULL,
        obligatorio BIT              NOT NULL,
        CONSTRAINT PK_PlantillaNotificacionMarcador PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_PlantillaNotificacionMarcador_tipo_marcador UNIQUE (tipo, marcador),
        CONSTRAINT CK_PlantillaNotificacionMarcador_marcador CHECK (marcador LIKE '[a-zA-Z]%' AND marcador NOT LIKE '%[^a-zA-Z0-9]%')
    );
END
GO

-- 3. Semillas idempotentes
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'estudiante', N'Nombre completo del estudiante retirado', N'Juan Pérez', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'motivo', N'Motivo del retiro registrado por el docente', N'Cancelación académica', 0),
    ('SOLICITUD_INGRESO_REGISTRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_REGISTRADA', 'estudiante', N'Nombre completo del estudiante solicitante', N'Juan Pérez', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'resultado', N'Resultado de la solicitud (aceptada, puesta en espera o rechazada)', N'aceptada', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'estudiante', N'Nombre completo del estudiante que retiró la solicitud', N'Juan Pérez', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET
        Target.descripcion = Source.descripcion,
        Target.ejemplo     = Source.ejemplo,
        Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'es', 1, N'Retiro del grupo {grupo}', N'Se registró el retiro de {estudiante} del grupo {grupo}.', 1),
    ('SOLICITUD_INGRESO_REGISTRADA', 'es', 1, N'Nueva solicitud de ingreso al grupo {grupo}', N'{estudiante} solicitó ingresar al grupo {grupo}. Revísala en la plataforma.', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'es', 1, N'Respuesta a tu solicitud de ingreso al grupo {grupo}', N'Tu solicitud de ingreso al grupo {grupo} fue {resultado}. Consulta el detalle en la plataforma.', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'es', 1, N'Solicitud de ingreso retirada del grupo {grupo}', N'{estudiante} retiró su solicitud de ingreso al grupo {grupo}.', 1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET
        Target.asunto = Source.asunto,
        Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
