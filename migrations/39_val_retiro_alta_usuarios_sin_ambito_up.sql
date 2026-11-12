-- ============================================================================
-- MIGRACION UP 39: VAL ROL-05 - retiro del alta de usuarios sin ambito (decision de John, 2026-11-12)
--   El backend retiro POST /api/v1/usuarios: cualquier usuario autenticado creaba un usuario y su cuenta en el proveedor de
--   identidad, sin ejecutor ni ambito. Esa ruta era la unica que llamaba al SP publico dbo.usp_sincronizar_usuario
--   (CC-003G-01), que por eso tampoco recibe ejecutor. Esta migracion retira su GRANT EXECUTE a rol_asistencias_runtime y el SP.
--   NO toca dbo.usp_sincronizar_usuario_interno: es el nucleo de los altas con ambito (usp_crear_decano_interno,
--   usp_crear_coordinador_interno, usp_vincular_docente_programa, usp_admitir_estudiante, usp_registrar_estudiante_en_grupo,
--   usp_internal_matricular_por_token) y sigue denegado al runtime (DENY de CC-003G-01).
-- Sin cambios de tablas ni de datos. Idempotente.
-- Down: 39_val_retiro_alta_usuarios_sin_ambito_down.sql (recrea el SP y su GRANT tal como estaban).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 39 UP: VAL ROL-05 retiro de usp_sincronizar_usuario (alta sin ambito)';
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_usuario', N'P') IS NOT NULL
   AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    REVOKE EXECUTE ON [dbo].[usp_sincronizar_usuario] FROM [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_usuario', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_sincronizar_usuario];
GO
IF OBJECT_ID(N'dbo.usp_sincronizar_usuario_interno', N'P') IS NULL
    THROW 53901, 'MIGRACION 39: usp_sincronizar_usuario_interno debe seguir existiendo (lo usan los altas con ambito).', 1;
GO
PRINT 'MIGRACION 39 UP OK';
GO
