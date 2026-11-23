-- ============================================================================
-- MIGRACION UP 70: correcciones de la auditoria de BD (2026-11-22), items M-11, M-1 y M-7.
--   M-11: ortografia (tildes) de 14 mensajes de usuario del catalogo (CatalogoMensajeUsuario; VAL_APP_068 tambien en CatalogoMensajeTecnico).
--   M-1:  indices de apoyo para las FK de ambito y filtro (IF NOT EXISTS; los mismos que declaran schema/tables/*.sql).
--   M-7:  retiro de ufn_obtener_estado_estudiante_grupo (sin ninguna referencia). usp_aplicar_festivos_grupo y
--         usp_consultar_oferta_creacion_grupo_docente se conservan: las usan pruebas de comportamiento y GRANT vigentes.
--   Los cuerpos de los SP y funciones cambiados por la auditoria (A-1, A-2, M-3, M-6) se despliegan con deploy_schema.ps1 (CREATE OR ALTER).
-- Idempotente. Down: 70_auditoria_bd_2026_11_22_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 70 UP: auditoria de BD 2026-11-22';
GO
-- [M-11] mensajes con tildes
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El código de correlación es requerido.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido <> N'El código de correlación es requerido.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El número de documento ya está registrado para este tipo de identificación.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_UNICIDAD_DOCUMENTO' AND contenido <> N'El número de documento ya está registrado para este tipo de identificación.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El estudiante no pertenece al grupo de la sesión seleccionada.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'EST_004' AND contenido <> N'El estudiante no pertenece al grupo de la sesión seleccionada.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El estudiante no pertenece al grupo de la sesión seleccionada.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_ESTUDIANTE_NO_PERTENECE_SESION' AND contenido <> N'El estudiante no pertenece al grupo de la sesión seleccionada.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El docente especificado no existe o está inactivo.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_DOCENTE_NO_EXISTE' AND contenido <> N'El docente especificado no existe o está inactivo.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El grupo seleccionado no existe o no está habilitado.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_GRUPO_NO_EXISTE' AND contenido <> N'El grupo seleccionado no existe o no está habilitado.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El grupo seleccionado no se encuentra habilitado para matrícula.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_GRUPO_NO_HABILITADO' AND contenido <> N'El grupo seleccionado no se encuentra habilitado para matrícula.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'La sesión de clase no existe o no está abierta.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_SESION_NO_EXISTE' AND contenido <> N'La sesión de clase no existe o no está abierta.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El código de verificación de asistencia es incorrecto o ha expirado.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_TOKEN_VERIFICACION_INVALIDO' AND contenido <> N'El código de verificación de asistencia es incorrecto o ha expirado.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El soporte indicado no está disponible para esta solicitud.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ARC_001' AND contenido <> N'El soporte indicado no está disponible para esta solicitud.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'Los datos del soporte no son válidos.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ARC_003' AND contenido <> N'Los datos del soporte no son válidos.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'Indica el período académico o el año, no ambos.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'FES_006' AND contenido <> N'Indica el período académico o el año, no ambos.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El período académico no existe.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'FES_007' AND contenido <> N'El período académico no existe.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El campo días es obligatorio cuando se envía el horario.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'VAL_APP_068' AND contenido <> N'El campo días es obligatorio cuando se envía el horario.';
GO
UPDATE [dbo].[CatalogoMensajeTecnico] SET contenido = N'Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo días es obligatorio cuando se envía el horario.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'VAL_APP_068' AND contenido <> N'Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo días es obligatorio cuando se envía el horario.';
GO
-- [FIN M-11]
-- [M-1] indices de apoyo para FK de ambito y filtro
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_docente')
    CREATE NONCLUSTERED INDEX IX_Grupo_docente ON dbo.Grupo (docente);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_periodoAcademico')
    CREATE NONCLUSTERED INDEX IX_Grupo_periodoAcademico ON dbo.Grupo (periodoAcademico);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_programaResponsable')
    CREATE NONCLUSTERED INDEX IX_Grupo_programaResponsable ON dbo.Grupo (programaResponsable);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_grupo')
    CREATE NONCLUSTERED INDEX IX_Horario_grupo ON dbo.Horario (grupo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_dia')
    CREATE NONCLUSTERED INDEX IX_Horario_dia ON dbo.Horario (dia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DocentePrograma') AND name = 'IX_DocentePrograma_programa')
    CREATE NONCLUSTERED INDEX IX_DocentePrograma_programa ON dbo.DocentePrograma (programa);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudiantePrograma') AND name = 'IX_EstudiantePrograma_programa')
    CREATE NONCLUSTERED INDEX IX_EstudiantePrograma_programa ON dbo.EstudiantePrograma (programa);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_facultad')
    CREATE NONCLUSTERED INDEX IX_Programa_facultad ON dbo.Programa (facultad);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_coordinador')
    CREATE NONCLUSTERED INDEX IX_Programa_coordinador ON dbo.Programa (coordinador);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PlanEstudio') AND name = 'IX_PlanEstudio_programa')
    CREATE NONCLUSTERED INDEX IX_PlanEstudio_programa ON dbo.PlanEstudio (programa);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SemestrePlanEstudio') AND name = 'IX_SemestrePlanEstudio_planEstudio')
    CREATE NONCLUSTERED INDEX IX_SemestrePlanEstudio_planEstudio ON dbo.SemestrePlanEstudio (planEstudio);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Coordinador') AND name = 'IX_Coordinador_facultad')
    CREATE NONCLUSTERED INDEX IX_Coordinador_facultad ON dbo.Coordinador (facultad);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Coordinador') AND name = 'IX_Coordinador_usuario')
    CREATE NONCLUSTERED INDEX IX_Coordinador_usuario ON dbo.Coordinador (usuario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Docente') AND name = 'IX_Docente_usuario')
    CREATE NONCLUSTERED INDEX IX_Docente_usuario ON dbo.Docente (usuario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Estudiante') AND name = 'IX_Estudiante_usuario')
    CREATE NONCLUSTERED INDEX IX_Estudiante_usuario ON dbo.Estudiante (usuario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Administrador') AND name = 'IX_Administrador_usuario')
    CREATE NONCLUSTERED INDEX IX_Administrador_usuario ON dbo.Administrador (usuario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Decano') AND name = 'IX_Decano_usuario')
    CREATE NONCLUSTERED INDEX IX_Decano_usuario ON dbo.Decano (usuario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Facultad') AND name = 'IX_Facultad_decano')
    CREATE NONCLUSTERED INDEX IX_Facultad_decano ON dbo.Facultad (decano);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_estado')
    CREATE NONCLUSTERED INDEX IX_EstudianteGrupo_estado ON dbo.EstudianteGrupo (estado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DetalleAsistencia') AND name = 'IX_DetalleAsistencia_razonCausa')
    CREATE NONCLUSTERED INDEX IX_DetalleAsistencia_razonCausa ON dbo.DetalleAsistencia (razonCausa);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_estado')
    CREATE NONCLUSTERED INDEX IX_SolicitudRevisionAsistencia_estado ON dbo.SolicitudRevisionAsistencia (estado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_toma')
    CREATE NONCLUSTERED INDEX IX_SolicitudRevisionAsistencia_toma ON dbo.SolicitudRevisionAsistencia (toma);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_estado')
    CREATE NONCLUSTERED INDEX IX_TomaAsistencia_estado ON dbo.TomaAsistencia (estado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_docenteApertura')
    CREATE NONCLUSTERED INDEX IX_TomaAsistencia_docenteApertura ON dbo.TomaAsistencia (docenteApertura);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_programaResolucion')
    CREATE NONCLUSTERED INDEX IX_RevisionCancelacion_programaResolucion ON dbo.RevisionCancelacion (programaResolucion);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_usuarioResolucion')
    CREATE NONCLUSTERED INDEX IX_RevisionCancelacion_usuarioResolucion ON dbo.RevisionCancelacion (usuarioResolucion);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionSolicitud') AND name = 'IX_SesionSolicitud_usuarioSolicitante')
    CREATE NONCLUSTERED INDEX IX_SesionSolicitud_usuarioSolicitante ON dbo.SesionSolicitud (usuarioSolicitante);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenMatriculaGrupo') AND name = 'IX_TokenMatriculaGrupo_docenteEmisor')
    CREATE NONCLUSTERED INDEX IX_TokenMatriculaGrupo_docenteEmisor ON dbo.TokenMatriculaGrupo (docenteEmisor);
GO
-- [FIN M-1]
-- [M-7] retiro de ufn_obtener_estado_estudiante_grupo (0 referencias en backend, frontend, SQL y pruebas; solo documentacion)
IF OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_obtener_estado_estudiante_grupo];
GO
-- [FIN M-7]
PRINT 'MIGRACION 70 UP: completada';
GO
