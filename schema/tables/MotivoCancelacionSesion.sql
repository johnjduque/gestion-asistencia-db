USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: catalogo de motivos con los que el coordinador del programa cancela una sesion creada manualmente por el
-- docente (usp_cancelar_sesion_coordinador). El codigo es estable (lo envia el cliente); el nombre es el texto institucional que
-- queda en SesionCancelacion.motivo. Filas en la semilla 60_sesiones_manuales_catalogos.sql (ids fijos).
IF OBJECT_ID('dbo.[MotivoCancelacionSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MotivoCancelacionSesion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     NVARCHAR(50)     NOT NULL,
        nombre     NVARCHAR(200)    NOT NULL,
        orden      INT              NOT NULL,
        estaActivo BIT              NOT NULL CONSTRAINT DF_MotivoCancelacionSesion_estaActivo DEFAULT 1,
        CONSTRAINT PK_MotivoCancelacionSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_MotivoCancelacionSesion_codigo UNIQUE (codigo),
        CONSTRAINT CK_MotivoCancelacionSesion_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
    );
END
GO
