USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Codigo sin uso (decision de John, 2026-10-29; informe informes/CODIGO_SIN_USO_BD_2026-10-29.md).
-- Elimina de las bases ya desplegadas 18 objetos que ni el backend ni ningun objeto en uso invoca
-- (deploy_schema.ps1 crea objetos pero no borra los que salen de schema/). Primero los publicos, luego
-- los internos que solo ellos usaban y por ultimo las funciones. Idempotente.
IF OBJECT_ID(N'dbo.usp_consultar_asignaturas_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_asignaturas_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_estudiante_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_asistencias_estudiante_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_docente_por_id', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_docente_por_id];
IF OBJECT_ID(N'dbo.usp_consultar_docentes_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_docentes_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_estudiante_por_id', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_estudiante_por_id];
IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_grupo_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_estudiantes_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_facultades_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_facultades_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_programas_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_programas_paginado];
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_asistencia_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_solicitudes_revision_asistencia_paginado];
IF OBJECT_ID(N'dbo.usp_resolver_solicitud_matricula', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_resolver_solicitud_matricula];
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_asistencia_estudiante];
IF OBJECT_ID(N'dbo.usp_registrar_docente_en_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_docente_en_grupo];
IF OBJECT_ID(N'dbo.usp_validar_estudiante_grupo_exista_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_estudiante_grupo_exista_interno];
IF OBJECT_ID(N'dbo.usp_registrar_docente_en_grupo_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_docente_en_grupo_interno];
IF OBJECT_ID(N'dbo.ufn_validar_password', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_validar_password];
IF OBJECT_ID(N'dbo.ufn_obtener_perfil_usuario_contexto', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_obtener_perfil_usuario_contexto];
IF OBJECT_ID(N'dbo.fn_diagramobjects', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[fn_diagramobjects];
GO
