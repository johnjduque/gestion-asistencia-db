USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): catalogo de estados de la solicitud de una sesion extraordinaria (aval previo del coordinador).
-- esFinal = 0 identifica el estado en espera (PENDIENTE); esAprobada distingue APROBADA de RECHAZADA entre los finales. Los SP
-- resuelven los estados por estas banderas, no por el texto del codigo. Filas en la semilla 60_sesiones_manuales_catalogos.sql.
IF OBJECT_ID('dbo.[EstadoSolicitudSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoSolicitudSesion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     NVARCHAR(30)     NOT NULL,
        nombre     NVARCHAR(100)    NOT NULL,
        orden      INT              NOT NULL,
        esFinal    BIT              NOT NULL,
        esAprobada BIT              NOT NULL CONSTRAINT DF_EstadoSolicitudSesion_esAprobada DEFAULT 0,
        CONSTRAINT PK_EstadoSolicitudSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoSolicitudSesion_codigo UNIQUE (codigo),
        CONSTRAINT CK_EstadoSolicitudSesion_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0),
        CONSTRAINT CK_EstadoSolicitudSesion_aprobada CHECK (esAprobada = 0 OR esFinal = 1)
    );
END
GO
