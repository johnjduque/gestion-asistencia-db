USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.10): permisos de ejecucion de las alertas de inasistencia, la revision de cancelacion y las audiencias
-- del SSE. Solo EXECUTE sobre los SP publicos (los usp_internal_* y las funciones no se conceden) y SELECT explicito de las
-- vistas nuevas (el bucle de rol_asistencias_runtime.sql esta congelado). Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_evaluar_alertas_inasistencia_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_evaluar_alertas_inasistencia_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_grupos_pendientes_evaluacion_alertas', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_grupos_pendientes_evaluacion_alertas] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_alertas_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_alertas_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_decidir_revision_cancelacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_decidir_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_revisiones_cancelacion_coordinador_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_decano_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_revisiones_cancelacion_decano_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_resolver_revision_cancelacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_resolver_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_revision_cancelacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_audiencias_realtime_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_audiencias_realtime_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_resolutores_revisiones_cancelacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_actualizar_resolutores_revisiones_cancelacion] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_tipo_alerta_inasistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_tipo_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_alerta_inasistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_revision_cancelacion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_transicion_revision_cancelacion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_transicion_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_alerta_inasistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_revision_cancelacion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_marca_inasistencia_estudiante_grupo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_marca_inasistencia_estudiante_grupo] TO [rol_asistencias_runtime];
GO
