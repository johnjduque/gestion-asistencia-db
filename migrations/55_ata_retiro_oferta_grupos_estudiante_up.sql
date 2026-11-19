-- ============================================================================
-- MIGRACION UP 55: ATA D11 retiro de la oferta de grupos del estudiante (HU008 descartada)
--   Decision del usuario (2026-11-18): el sistema solo gestiona asistencia; la inscripcion a grupos la gestiona otro
--   sistema y el estudiante solo se matricula por QR/PIN del docente (HU176B) o lo matricula el docente (HU050).
--   Elimina usp_consultar_oferta_grupos_estudiante y el parametro OFERTA/INCLUIR_TRANSVERSALES (con su metadato de
--   edicion y su historial de cambios), que solo usaba ese SP. No toca usp_consultar_oferta_creacion_grupo_docente.
--   deploy_schema.ps1 no borra objetos, por eso el retiro vive aqui. Idempotente. Down: 55_..._down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 55 UP: ATA D11 retiro de la oferta de grupos del estudiante';
GO
IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_oferta_grupos_estudiante];
GO
DELETE c FROM dbo.CambioParametro c
INNER JOIN dbo.CatalogoParametro p ON p.id = c.parametro
WHERE p.grupo = 'OFERTA' AND p.clave = 'INCLUIR_TRANSVERSALES';
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
    DELETE e FROM dbo.CatalogoParametroEdicion e
    INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    WHERE p.grupo = 'OFERTA' AND p.clave = 'INCLUIR_TRANSVERSALES';
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES';
GO
IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES')
    THROW 55001, 'MIGRACION 55: quedaron objetos de la oferta de grupos del estudiante.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_oferta_creacion_grupo_docente', N'P') IS NULL
    THROW 55002, 'MIGRACION 55: la oferta del docente para crear grupos debe seguir disponible.', 1;
GO
PRINT 'MIGRACION 55 UP OK';
GO
