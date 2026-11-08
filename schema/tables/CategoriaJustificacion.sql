USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU005/HU016: categorias con las que el estudiante justifica una inasistencia o llegada tarde al radicar un reclamo.
-- Catalogo base de solo consulta (regla de John, 2026-11-04): se carga por seed, sin SP de escritura.
-- CULM-001 D.2 (TD-060): SolicitudRevisionAsistencia.categoriaJustificacion referencia esta tabla (FK en zz_foreign_keys.sql) y
-- requiereSoporte indica si la categoria exige adjuntar al menos un soporte (HU014: MED, ACA y LAB; seed 52_culm001_d2_*).
IF OBJECT_ID('dbo.CategoriaJustificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CategoriaJustificacion (
        id          UNIQUEIDENTIFIER NOT NULL,
        codigo      NVARCHAR(5)      NOT NULL,
        nombre      NVARCHAR(50)     NOT NULL,
        descripcion NVARCHAR(250)    NULL,
        CONSTRAINT PK_CategoriaJustificacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_CategoriaJustificacion_codigo UNIQUE (codigo),
        CONSTRAINT UQ_CategoriaJustificacion_nombre UNIQUE (nombre)
    );
END
GO

-- CULM-001 D.2: soporte obligatorio por categoria (el valor lo fija el seed, sin literales de categoria en los SP).
IF COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NULL
    ALTER TABLE dbo.CategoriaJustificacion ADD [requiereSoporte] bit NOT NULL
        CONSTRAINT DF_CategoriaJustificacion_requiereSoporte DEFAULT 0;
GO
