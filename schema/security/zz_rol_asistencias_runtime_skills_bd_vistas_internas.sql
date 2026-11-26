USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 16 (2026-11-26): las 32 vistas uv_* que crearon los lotes 2 a 14 son vistas de lectura INTERNA de los SP
-- (proyecciones de sus tablas). El grant generico de rol_asistencias_runtime.sql concede SELECT sobre toda vista uv_*, y como
-- vista y tabla tienen el mismo dueno, ese SELECT pasaria por encima de los DENY de tabla (p. ej. dbo.ArchivoSoporte en
-- rol_asistencias_runtime_lb004d.sql) y le daria al backend tablas que nunca leyo (notificaciones, tokens, soportes, revisiones).
-- El backend no usa ninguna de estas vistas (verificado contra develop del backend 2026-11-26), asi que se niegan aqui.
-- Los SP las siguen leyendo por encadenamiento de propiedad (mismo dueno dbo), que no evalua permisos sobre la vista.
-- El prefijo zz_ hace que deploy_schema.ps1 ejecute este script despues del grant generico (ordena los scripts por nombre).
-- Script idempotente. Lo comprueba test/test_skills_lote16_correcciones.sql (SKL16_S01_VISTAS_INTERNAS_SIN_SELECT).
-- Una vista interna nueva se agrega a esta lista; una vista que el backend deba leer NO va aqui (E3 de excepciones-skills-bd.md).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @vistasInternas TABLE (nombre SYSNAME PRIMARY KEY);
INSERT INTO @vistasInternas (nombre) VALUES
    (N'uv_administrador_registro'),
    (N'uv_archivo_soporte_registro'),
    (N'uv_asignatura_registro'),
    (N'uv_asistencia_registro'),
    (N'uv_aviso_falta_sesion'),
    (N'uv_aviso_sesion_sin_toma'),
    (N'uv_decano_rol'),
    (N'uv_detalle_asistencia_registro'),
    (N'uv_estado_notificacion'),
    (N'uv_estudiante_grupo_registro'),
    (N'uv_estudiante_programa_registro'),
    (N'uv_estudiante_programa_semestre'),
    (N'uv_evaluacion_alerta_grupo'),
    (N'uv_facultad_registro'),
    (N'uv_grupo_registro'),
    (N'uv_horario_registro'),
    (N'uv_notificacion_saliente'),
    (N'uv_parametro_edicion_registro'),
    (N'uv_parametro_registro'),
    (N'uv_periodo_academico_fechas'),
    (N'uv_programa_registro'),
    (N'uv_receso_academico_registro'),
    (N'uv_revision_cancelacion_registro'),
    (N'uv_sesion_cancelacion'),
    (N'uv_sesion_procedencia_clasificacion_registro'),
    (N'uv_sesion_registro'),
    (N'uv_sincronizacion_parametro_externo_registro'),
    (N'uv_solicitud_revision_asistencia_registro'),
    (N'uv_solicitud_sesion_registro'),
    (N'uv_token_matricula_grupo_registro'),
    (N'uv_token_verificacion_correo'),
    (N'uv_toma_asistencia_registro');

DECLARE @faltantes NVARCHAR(MAX) = (
    SELECT STRING_AGG(v.nombre, N', ')
    FROM @vistasInternas AS v
    WHERE OBJECT_ID(N'dbo.' + v.nombre, N'V') IS NULL
);
IF @faltantes IS NOT NULL
    THROW 53052, 'SKILLS_BD_LOTE16_DENY: vista interna requerida ausente.', 1;

DECLARE @sql NVARCHAR(MAX) = (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), N'DENY SELECT ON [dbo].' + QUOTENAME(v.nombre) + N' TO [rol_asistencias_runtime];'), NCHAR(10))
    FROM @vistasInternas AS v
);
EXEC sys.sp_executesql @sql;
GO
