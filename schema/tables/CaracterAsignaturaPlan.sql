USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- CULM-001 B2NM (DEC-019): catalogo del caracter de una asignatura dentro de un plan (OBL, OPT). Solo consulta.
IF OBJECT_ID('dbo.CaracterAsignaturaPlan', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CaracterAsignaturaPlan (
        id      UNIQUEIDENTIFIER NOT NULL,
        codigo  NVARCHAR(3)      NOT NULL,
        nombre  NVARCHAR(50)     NOT NULL,
        orden   INT              NOT NULL,
        estado  BIT              NOT NULL CONSTRAINT DF_CaracterAsignaturaPlan_estado DEFAULT (1),
        CONSTRAINT PK_CaracterAsignaturaPlan PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_CaracterAsignaturaPlan_codigo UNIQUE (codigo),
        CONSTRAINT UQ_CaracterAsignaturaPlan_nombre UNIQUE (nombre),
        CONSTRAINT UQ_CaracterAsignaturaPlan_orden UNIQUE (orden)
    );
END
