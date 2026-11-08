USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1, SUPUESTO-C-07): transiciones validas de la revision de cancelacion.
IF OBJECT_ID('dbo.[TransicionRevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TransicionRevisionCancelacion (
        id                          UNIQUEIDENTIFIER NOT NULL,
        estadoOrigen                UNIQUEIDENTIFIER NOT NULL,
        codigoDecision              NVARCHAR(20)     NOT NULL,
        esDecisionResolutor         BIT              NOT NULL,
        estadoDestino               UNIQUEIDENTIFIER NOT NULL,
        exigeUmbralPerdida          BIT              NOT NULL,
        exigeResolutorDisponible    BIT              NOT NULL,
        codigoMensajeExito          VARCHAR(100)     NOT NULL,
        tipoPlantillaNotificacion   VARCHAR(60)      NULL,
        CONSTRAINT PK_TransicionRevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TransicionRevisionCancelacion_origen_decision UNIQUE (estadoOrigen, codigoDecision)
    );
END
GO
