USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Migracion 65: permisos del runtime para administrar las categorias de justificacion y los motivos de cancelacion de sesion.
-- Cada SP publico exige el perfil ADMINISTRADOR; los validadores internos solo se alcanzan por encadenamiento de propiedad.
-- Script aditivo e idempotente. Las vistas uv_* nuevas reciben SELECT en rol_asistencias_runtime.sql (cursor sobre uv_%).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_crear_categoria_justificacion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_crear_categoria_justificacion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_actualizar_categoria_justificacion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_actualizar_categoria_justificacion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_categoria_justificacion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_cambiar_estado_categoria_justificacion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_crear_motivo_cancelacion_sesion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_crear_motivo_cancelacion_sesion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_actualizar_motivo_cancelacion_sesion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_actualizar_motivo_cancelacion_sesion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_cambiar_estado_motivo_cancelacion_sesion', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_cambiar_estado_motivo_cancelacion_sesion requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_validar_ejecutor_administrador_interno', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_validar_ejecutor_administrador_interno requerido ausente.', 1;
GO
IF OBJECT_ID(N'dbo.usp_validar_item_catalogo_interno', N'P') IS NULL
    THROW 52741, 'ADMIN_CATALOGOS_RUNTIME_GRANT: usp_validar_item_catalogo_interno requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_crear_categoria_justificacion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_categoria_justificacion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_categoria_justificacion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_motivo_cancelacion_sesion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_motivo_cancelacion_sesion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_motivo_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
DENY EXECUTE ON [dbo].[usp_validar_ejecutor_administrador_interno] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_validar_item_catalogo_interno] TO [rol_asistencias_runtime];
GO
