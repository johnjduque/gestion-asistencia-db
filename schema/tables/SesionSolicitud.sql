USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): solicitud de una sesion extraordinaria (1:0..1 con dbo.Sesion, que no se modifica: su guard 50004 prohibe
-- columnas de estado). La crea usp_crear_sesion_interno cuando el docente crea una sesion manual; la resuelven
-- usp_aprobar_solicitud_sesion / usp_rechazar_solicitud_sesion (el coordinador del programa). Las sesiones sin fila (generadas,
-- anteriores a este cambio) no tienen solicitud. Las FK estan en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[SesionSolicitud]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SesionSolicitud (
        sesion              UNIQUEIDENTIFIER NOT NULL,
        idEstado            UNIQUEIDENTIFIER NOT NULL,
        usuarioSolicitante  UNIQUEIDENTIFIER NOT NULL,
        fechaSolicitudUtc   DATETIME2(0)     NOT NULL CONSTRAINT DF_SesionSolicitud_fechaSolicitud DEFAULT SYSUTCDATETIME(),
        usuarioResolucion   UNIQUEIDENTIFIER NULL,
        fechaResolucionUtc  DATETIME2(0)     NULL,
        observacion         NVARCHAR(500)    NULL,
        idCorrelacion       UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_SesionSolicitud PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_SesionSolicitud_resolucion CHECK ((usuarioResolucion IS NULL AND fechaResolucionUtc IS NULL)
                                                      OR (usuarioResolucion IS NOT NULL AND fechaResolucionUtc IS NOT NULL))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionSolicitud') AND name = 'IX_SesionSolicitud_idEstado')
    CREATE NONCLUSTERED INDEX IX_SesionSolicitud_idEstado ON dbo.SesionSolicitud (idEstado) INCLUDE (fechaSolicitudUtc);
GO
