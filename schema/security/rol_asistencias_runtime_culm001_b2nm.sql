USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.8.2): permisos de minimo privilegio de las asignaturas por plan y del ambito por relacion.
-- Aditivo e idempotente (patron rol_asistencias_runtime_hu081_hu083.sql); no edita rol_asistencias_runtime.sql.
--   * GRANT EXECUTE a los SP publicos nuevos; DENY EXECUTE a los internos.
--   * DENY INSERT/UPDATE/DELETE en las tablas nuevas y en EstudiantePrograma (se escriben solo por SP, encadenamiento dbo -> dbo).
--   * GRANT SELECT a las TVF nuevas.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @requeridos TABLE (nombre SYSNAME);
INSERT INTO @requeridos VALUES
    (N'usp_asociar_asignatura_plan'), (N'usp_desvincular_asignatura_plan'), (N'usp_consultar_asignaturas_plan_paginado'),
    (N'usp_consultar_asignaturas_asociables_paginado'), (N'usp_consultar_asignaturas_coordinador_paginado'),
    (N'usp_consultar_planes_estudio_programa_paginado'), (N'usp_consultar_grupos_facultad_paginado'), (N'usp_consultar_programas_grupo'),
    (N'usp_internal_asociar_asignatura_plan'), (N'usp_internal_asegurar_estudiante_programa_grupo');
DECLARE @faltante SYSNAME = (SELECT TOP 1 nombre FROM @requeridos WHERE OBJECT_ID(CONCAT(N'dbo.', nombre), N'P') IS NULL);
IF @faltante IS NOT NULL
BEGIN
    DECLARE @msg NVARCHAR(400) = CONCAT(N'CULM001_B2NM_RUNTIME_GRANT: procedimiento requerido ausente: ', @faltante);
    THROW 52930, @msg, 1;
END
GO

GRANT EXECUTE ON [dbo].[usp_asociar_asignatura_plan] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_desvincular_asignatura_plan] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_plan_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_asociables_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_coordinador_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_planes_estudio_programa_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_grupos_facultad_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_programas_grupo] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_internal_asociar_asignatura_plan] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_internal_asegurar_estudiante_programa_grupo] TO [rol_asistencias_runtime];
GO

DENY INSERT, UPDATE, DELETE ON [dbo].[AsignaturaPlanEstudio] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[CaracterAsignaturaPlan] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[EstudiantePrograma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.zz_reporte_culm001_b2nm_estudiante_programa', N'U') IS NOT NULL
    DENY INSERT, UPDATE, DELETE ON [dbo].[zz_reporte_culm001_b2nm_estudiante_programa] TO [rol_asistencias_runtime];
GO

GRANT SELECT ON [dbo].[ufn_programas_grupo] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_programas_coordinador] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_programas_ambito_ejecutor] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_estudiantes_grupo_visibles] TO [rol_asistencias_runtime];
GO

DECLARE @v SYSNAME, @sql NVARCHAR(400);
DECLARE vistas CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID(N'dbo') AND name IN
        (N'uv_caracter_asignatura_plan', N'uv_asignatura_plan_estudio', N'uv_estudiante_grupo_programa', N'uv_resumen_asistencia_estudiante_programa_grupo');
OPEN vistas; FETCH NEXT FROM vistas INTO @v;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CONCAT(N'GRANT SELECT ON [dbo].', QUOTENAME(@v), N' TO [rol_asistencias_runtime];');
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM vistas INTO @v;
END
CLOSE vistas; DEALLOCATE vistas;
GO
