-- ============================================================================
-- MIGRACION DOWN 54: retira ATA D10 (SP de faltas reclamables del estudiante y su vista). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 54 DOWN: retira ATA D10';
GO
IF OBJECT_ID(N'dbo.usp_consultar_faltas_reclamables_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_faltas_reclamables_estudiante];
IF OBJECT_ID(N'dbo.uv_falta_reclamable_estudiante', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_falta_reclamable_estudiante];
GO
PRINT 'MIGRACION 54 DOWN OK';
GO
