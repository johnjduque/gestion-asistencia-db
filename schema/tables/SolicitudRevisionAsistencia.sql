USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[SolicitudRevisionAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SolicitudRevisionAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [fecha] date NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [justificacionSolicitud] varchar(MAX) NOT NULL,
    [justificacionRespuesta] varchar(MAX) NOT NULL
);

ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD CONSTRAINT [PK__Solicitu__3213E83F81F5487B] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 D.2 (TD-060, HU014/HU015): categoria con la que el estudiante justifico el reclamo (FK a CategoriaJustificacion en
-- zz_foreign_keys.sql). Sin backfill: los reclamos anteriores quedan con NULL (el formulario anterior no la persistia).
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [categoriaJustificacion] uniqueidentifier NULL;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B): reclamo por toma.
--   toma                  toma reclamada (FK a TomaAsistencia); NULL = reclamo de la sesion completa (v2/v3, legado).
--   razonCausaResolucion  resultado de una aprobacion (FK a RazonCausa): AN = estuvo presente, EX = ausencia justificada;
--                         NULL mientras no se apruebe y en los reclamos aprobados antes de PC.
-- FKs e indice (asistencia, toma) en zz_foreign_keys.sql. Sin backfill.
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'toma') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [toma] uniqueidentifier NULL;
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'razonCausaResolucion') IS NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] ADD [razonCausaResolucion] uniqueidentifier NULL;
GO
