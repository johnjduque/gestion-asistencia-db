USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081: permisos del rol runtime sobre el receso academico del periodo. Aditivo e idempotente (no modifica rol_asistencias_runtime.sql).
-- Los nucleos usp_validar_receso_academico_interno y usp_internal_cancelar_sesiones_receso NO se conceden (encadenamiento de propiedad).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_crear_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_retirar_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_recesos_periodo', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_periodo_receso_academico', N'V') IS NULL
    THROW 52970, 'RECESO_ACADEMICO_RUNTIME_GRANT: objeto requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_crear_receso_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_retirar_receso_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_recesos_periodo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_receso_academico] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[uv_periodo_receso_academico] TO [rol_asistencias_runtime];
GO
