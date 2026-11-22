USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.1): catalogo del tipo de cancelacion de una sesion. esAutomatica: 1 = la crea el sistema (dia festivo
-- FESTIVO o receso academico RECESO); 0 = la decide el docente. Hay un solo tipo manual; los automaticos se resuelven por codigo
-- (parametros SESION/CODIGO_TIPO_CANCELACION_FESTIVO y RECESO/CODIGO_TIPO_CANCELACION). DEC-081 (migracion 68) retiro la unicidad por
-- bandera (UQ_TipoCancelacionSesion_esAutomatica), que impedia tener dos tipos automaticos. Filas en la semilla 34 (ids fijos).
IF OBJECT_ID('dbo.[TipoCancelacionSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TipoCancelacionSesion (
        id            UNIQUEIDENTIFIER NOT NULL,
        codigo        NVARCHAR(20)     NOT NULL,
        nombre        NVARCHAR(50)     NOT NULL,
        esAutomatica  BIT              NOT NULL,
        CONSTRAINT PK_TipoCancelacionSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TipoCancelacionSesion_codigo UNIQUE (codigo)
    );
END
GO

-- DEC-081 (migracion 68): bases anteriores retiran la unicidad por bandera para admitir el tipo automatico RECESO.
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_TipoCancelacionSesion_esAutomatica' AND parent_object_id = OBJECT_ID('dbo.TipoCancelacionSesion'))
    ALTER TABLE dbo.TipoCancelacionSesion DROP CONSTRAINT UQ_TipoCancelacionSesion_esAutomatica;
GO
