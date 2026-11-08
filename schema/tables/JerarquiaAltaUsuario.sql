USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, [SUPUESTO-D-15], HU171): jerarquia de alta masiva de usuarios.
-- Tabla de catalogo que define los pares permitidos de (perfilEjecutor -> perfilDestino)
-- para la carga masiva CSV.
-- Filas sembradas (55_culm001_d5_jerarquia.sql):
--   COORDINADOR -> DOCENTE
--   DECANO      -> COORDINADOR
--   ADMINISTRADOR -> DECANO
-- ============================================================================
IF OBJECT_ID('dbo.[JerarquiaAltaUsuario]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.JerarquiaAltaUsuario (
        id             UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_JerarquiaAltaUsuario PRIMARY KEY CLUSTERED,
        perfilEjecutor UNIQUEIDENTIFIER NOT NULL,
        perfilDestino  UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_JerarquiaAltaUsuario_Pares UNIQUE (perfilEjecutor, perfilDestino)
    );
END
GO
