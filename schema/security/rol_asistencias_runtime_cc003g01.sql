USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CC-003G-01: permisos de minimo privilegio del proveedor publico de plan de estudio.
-- VAL ROL-05 (2026-11-12, migracion 39): el proveedor publico usp_sincronizar_usuario (alta de usuarios sin ejecutor ni
-- ambito, usado solo por POST /api/v1/usuarios) se retiro con su GRANT. El nucleo usp_sincronizar_usuario_interno sigue
-- denegado al runtime: solo lo usan los altas con ambito por encadenamiento de propiedad.
--
-- Script aditivo e independiente de UTC-D06: no modifica rol_asistencias_runtime.sql (cuyo hash esta
-- fijado en DB_UTC_D06_POST_FREEZE_MANIFEST.sha256). Es idempotente y no depende del orden de despliegue
-- respecto a ese script. Reglas:
--   * Solo EXEC del SP publico nombrado; nunca GRANT EXECUTE ON SCHEMA::dbo.
--   * El nucleo usp_sincronizar_usuario_interno queda explicitamente denegado al runtime.
--   * Sin DML directo del runtime sobre dbo.Usuario ni dbo.PlanEstudio: toda escritura pasa por los SP
--     (encadenamiento de propiedad dbo -> dbo).
--   * Este script crea roles pero NO logins ni membresias (decision de despliegue por ambiente).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_registrar_o_actualizar_plan_estudio', N'P') IS NULL
    THROW 52131, 'CC_003G_01_RUNTIME_GRANT: usp_registrar_o_actualizar_plan_estudio requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_registrar_o_actualizar_plan_estudio] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_sincronizar_usuario_interno] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[Usuario] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[PlanEstudio] TO [rol_asistencias_runtime];
GO
