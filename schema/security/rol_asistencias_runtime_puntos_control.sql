USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- PC (puntos de control, docs/work-items/PC-puntos-control-tomas): permisos del rol runtime para lo nuevo. Aditivo e idempotente.
--   EXECUTE: usp_radicar_solicitud_revision_asistencia_v4 (reclamo por toma) y usp_consultar_resumen_tomas_sesion (docente).
--   SELECT:  uv_asistencia_toma_estudiante (la lee el backend por JPA). uv_asistencia_sesion_horas y uv_toma_asistencia ya
--            tienen SELECT (rol_asistencias_runtime_culm001_b2.sql). Las vistas uv_* reciben ademas el SELECT generico de
--            rol_asistencias_runtime.sql; este archivo lo deja explicito para la vista que consume el backend.
-- usp_internal_radicar_solicitud_revision sigue sin concederse (encadenamiento de propiedad).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v4', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_radicar_solicitud_revision_asistencia_v4] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_resumen_tomas_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_resumen_tomas_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_asistencia_toma_estudiante', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_asistencia_toma_estudiante] TO [rol_asistencias_runtime];
GO
