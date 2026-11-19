USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): marca de que una sesion terminada ya fue avisada por correo a los estudiantes con falta
-- (un aviso por estudiante y sesion). Una fila = sesion ya avisada; la escribe usp_registrar_aviso_falta_sesion (idempotente) y la lee
-- usp_consultar_sesiones_pendientes_aviso_falta. La FK a Sesion esta en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[AvisoFaltaSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvisoFaltaSesion (
        sesion                   UNIQUEIDENTIFIER NOT NULL,
        fechaAvisoUtc            DATETIME2(3)     NOT NULL,
        totalEstudiantesAvisados INT              NOT NULL,
        idCorrelacion            UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_AvisoFaltaSesion PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_AvisoFaltaSesion_total CHECK (totalEstudiantesAvisados >= 0)
    );
END
GO
