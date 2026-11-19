USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTOMA-001 (AsistenciasUCO-Infra/docs/work-items/NOTOMA-001-aviso-coordinador-sesion-sin-toma): marca de que una sesion terminada sin ninguna toma
-- de asistencia ya fue avisada por correo a la coordinacion del programa (un aviso por sesion). Una fila = sesion ya avisada; la escribe
-- usp_registrar_aviso_sesion_sin_toma (idempotente) y la lee usp_consultar_sesiones_pendientes_aviso_sin_toma. La FK a Sesion esta en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[AvisoSesionSinToma]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvisoSesionSinToma (
        sesion                     UNIQUEIDENTIFIER NOT NULL,
        fechaAvisoUtc              DATETIME2(3)     NOT NULL,
        totalCoordinadoresAvisados INT              NOT NULL,
        idCorrelacion              UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_AvisoSesionSinToma PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_AvisoSesionSinToma_total CHECK (totalCoordinadoresAvisados >= 0)
    );
END
GO
