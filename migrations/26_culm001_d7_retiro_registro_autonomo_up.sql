-- ============================================================================
-- MIGRACION UP 26: CULM-001 D.7 - retira usp_registrar_asistencia_estudiante_autonomo (CONTRACT D 8.2, TD-009, HU027)
-- El registro individual del estudiante queda cubierto por el lote (usp_registrar_asistencias_sesion), por la toma
-- (usp_registrar_asistencias_toma) y por el token (usp_registrar_asistencia_por_token) de B.2. REVOKE EXECUTE del rol runtime
-- (si existe el rol y el SP) y DROP PROCEDURE. Idempotente. Down: 26_..._down.sql recrea el SP con su texto literal y el GRANT.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 26 UP: retiro del registro autonomo (D.7)';
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
   AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    REVOKE EXECUTE ON [dbo].[usp_registrar_asistencia_estudiante_autonomo] FROM [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante_autonomo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_asistencia_estudiante_autonomo];
GO
