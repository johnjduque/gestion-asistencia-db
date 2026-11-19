-- ============================================================================
-- MIGRACION DOWN 52: retira ATA D6/D7 (SP de solicitudes del docente, calendario de sesiones y sus permisos). El mensaje CAL_001
-- se conserva (catalogo de solo anexar). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 52 DOWN: retira ATA D6/D7';
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_docente_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_solicitudes_sesion_docente_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_sesiones_calendario_estudiante];
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_docente', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_sesiones_calendario_docente];
IF OBJECT_ID(N'dbo.usp_validar_rango_calendario_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_rango_calendario_interno];
IF OBJECT_ID(N'dbo.uv_sesion_calendario', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_sesion_calendario];
GO
PRINT 'MIGRACION 52 DOWN OK';
GO
