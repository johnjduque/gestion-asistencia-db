-- ============================================================================
-- MIGRACION DOWN 30: HU018 / HU019 - retira el plan de estudios y las horas programadas del estudiante
--   DROP de usp_consultar_plan_estudio_estudiante y usp_consultar_horas_programadas_estudiante (sus permisos se van con ellos).
-- No toca tablas, vistas ni datos: los dos SP son de solo lectura. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 30 DOWN: retira el plan de estudios y las horas programadas del estudiante';
GO
IF OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_plan_estudio_estudiante;
GO
IF OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_horas_programadas_estudiante;
GO
PRINT 'MIGRACION 30 DOWN OK';
GO
