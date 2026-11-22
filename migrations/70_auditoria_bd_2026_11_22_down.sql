-- ============================================================================
-- MIGRACION DOWN 70: revierte las correcciones de la auditoria de BD (2026-11-22): textos anteriores de los mensajes (M-11), retira los
-- indices (M-1) y recrea la funcion retirada (M-7). Los cuerpos de SP y funciones de A-1, A-2, M-3 y M-6 se revierten desplegando
-- la version anterior del esquema (git). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 70 DOWN: auditoria de BD 2026-11-22';
GO
-- [M-11] mensajes con el texto anterior
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El codigo de correlacion es requerido.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido <> N'El codigo de correlacion es requerido.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El numero de documento ya esta registrado para este tipo de identificacion.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_UNICIDAD_DOCUMENTO' AND contenido <> N'El numero de documento ya esta registrado para este tipo de identificacion.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El estudiante no pertenece al grupo de la sesion seleccionada.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'EST_004' AND contenido <> N'El estudiante no pertenece al grupo de la sesion seleccionada.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El estudiante no pertenece al grupo de la sesion seleccionada.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_ESTUDIANTE_NO_PERTENECE_SESION' AND contenido <> N'El estudiante no pertenece al grupo de la sesion seleccionada.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El docente especificado no existe o esta inactivo.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_DOCENTE_NO_EXISTE' AND contenido <> N'El docente especificado no existe o esta inactivo.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El grupo seleccionado no existe o no esta habilitado.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_GRUPO_NO_EXISTE' AND contenido <> N'El grupo seleccionado no existe o no esta habilitado.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El grupo seleccionado no se encuentra habilitado para matricula.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_GRUPO_NO_HABILITADO' AND contenido <> N'El grupo seleccionado no se encuentra habilitado para matricula.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'La sesion de clase no existe o no esta abierta.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_SESION_NO_EXISTE' AND contenido <> N'La sesion de clase no existe o no esta abierta.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El codigo de verificacion de asistencia es incorrecto o ha expirado.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ERR_TOKEN_VERIFICACION_INVALIDO' AND contenido <> N'El codigo de verificacion de asistencia es incorrecto o ha expirado.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El soporte indicado no esta disponible para esta solicitud.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ARC_001' AND contenido <> N'El soporte indicado no esta disponible para esta solicitud.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'Los datos del soporte no son validos.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'ARC_003' AND contenido <> N'Los datos del soporte no son validos.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'Indica el periodo académico o el año, no ambos.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'FES_006' AND contenido <> N'Indica el periodo académico o el año, no ambos.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El periodo académico no existe.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'FES_007' AND contenido <> N'El periodo académico no existe.';
GO
UPDATE [dbo].[CatalogoMensajeUsuario] SET contenido = N'El campo dias es obligatorio cuando se envía el horario.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'VAL_APP_068' AND contenido <> N'El campo dias es obligatorio cuando se envía el horario.';
GO
UPDATE [dbo].[CatalogoMensajeTecnico] SET contenido = N'Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo dias es obligatorio cuando se envia el horario.', fechaModificacion = SYSUTCDATETIME() WHERE codigo = 'VAL_APP_068' AND contenido <> N'Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo dias es obligatorio cuando se envia el horario.';
GO
-- [FIN M-11]
-- [M-1] retira los indices de apoyo
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_docente')
    DROP INDEX IX_Grupo_docente ON dbo.Grupo;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_periodoAcademico')
    DROP INDEX IX_Grupo_periodoAcademico ON dbo.Grupo;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_programaResponsable')
    DROP INDEX IX_Grupo_programaResponsable ON dbo.Grupo;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_grupo')
    DROP INDEX IX_Horario_grupo ON dbo.Horario;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Horario') AND name = 'IX_Horario_dia')
    DROP INDEX IX_Horario_dia ON dbo.Horario;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DocentePrograma') AND name = 'IX_DocentePrograma_programa')
    DROP INDEX IX_DocentePrograma_programa ON dbo.DocentePrograma;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudiantePrograma') AND name = 'IX_EstudiantePrograma_programa')
    DROP INDEX IX_EstudiantePrograma_programa ON dbo.EstudiantePrograma;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_facultad')
    DROP INDEX IX_Programa_facultad ON dbo.Programa;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Programa') AND name = 'IX_Programa_coordinador')
    DROP INDEX IX_Programa_coordinador ON dbo.Programa;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PlanEstudio') AND name = 'IX_PlanEstudio_programa')
    DROP INDEX IX_PlanEstudio_programa ON dbo.PlanEstudio;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SemestrePlanEstudio') AND name = 'IX_SemestrePlanEstudio_planEstudio')
    DROP INDEX IX_SemestrePlanEstudio_planEstudio ON dbo.SemestrePlanEstudio;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Coordinador') AND name = 'IX_Coordinador_facultad')
    DROP INDEX IX_Coordinador_facultad ON dbo.Coordinador;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Coordinador') AND name = 'IX_Coordinador_usuario')
    DROP INDEX IX_Coordinador_usuario ON dbo.Coordinador;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Docente') AND name = 'IX_Docente_usuario')
    DROP INDEX IX_Docente_usuario ON dbo.Docente;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Estudiante') AND name = 'IX_Estudiante_usuario')
    DROP INDEX IX_Estudiante_usuario ON dbo.Estudiante;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Administrador') AND name = 'IX_Administrador_usuario')
    DROP INDEX IX_Administrador_usuario ON dbo.Administrador;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Decano') AND name = 'IX_Decano_usuario')
    DROP INDEX IX_Decano_usuario ON dbo.Decano;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Facultad') AND name = 'IX_Facultad_decano')
    DROP INDEX IX_Facultad_decano ON dbo.Facultad;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name = 'IX_EstudianteGrupo_estado')
    DROP INDEX IX_EstudianteGrupo_estado ON dbo.EstudianteGrupo;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DetalleAsistencia') AND name = 'IX_DetalleAsistencia_razonCausa')
    DROP INDEX IX_DetalleAsistencia_razonCausa ON dbo.DetalleAsistencia;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_estado')
    DROP INDEX IX_SolicitudRevisionAsistencia_estado ON dbo.SolicitudRevisionAsistencia;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_toma')
    DROP INDEX IX_SolicitudRevisionAsistencia_toma ON dbo.SolicitudRevisionAsistencia;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_estado')
    DROP INDEX IX_TomaAsistencia_estado ON dbo.TomaAsistencia;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_docenteApertura')
    DROP INDEX IX_TomaAsistencia_docenteApertura ON dbo.TomaAsistencia;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_programaResolucion')
    DROP INDEX IX_RevisionCancelacion_programaResolucion ON dbo.RevisionCancelacion;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_usuarioResolucion')
    DROP INDEX IX_RevisionCancelacion_usuarioResolucion ON dbo.RevisionCancelacion;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionSolicitud') AND name = 'IX_SesionSolicitud_usuarioSolicitante')
    DROP INDEX IX_SesionSolicitud_usuarioSolicitante ON dbo.SesionSolicitud;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenMatriculaGrupo') AND name = 'IX_TokenMatriculaGrupo_docenteEmisor')
    DROP INDEX IX_TokenMatriculaGrupo_docenteEmisor ON dbo.TokenMatriculaGrupo;
GO
-- [FIN M-1]
-- [M-7] recrea ufn_obtener_estado_estudiante_grupo (cuerpo identico al retirado)
IF OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo', N'FN') IS NULL
    EXEC(N'CREATE FUNCTION [dbo].[ufn_obtener_estado_estudiante_grupo]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idGrupo      UNIQUEIDENTIFIER
)
RETURNS NVARCHAR(100)
AS
BEGIN
    DECLARE @nombreEstado NVARCHAR(100) = N''NO INSCRITO'';

    SELECT TOP 1
        @nombreEstado = eg.nombreEstadoEstudiante
    FROM dbo.uv_estudiante_grupo eg
    WHERE eg.idEstudiante = @idEstudiante
      AND eg.idGrupo = @idGrupo;

    RETURN ISNULL(@nombreEstado, N''NO INSCRITO'');
END');
GO
-- [FIN M-7]
PRINT 'MIGRACION 70 DOWN: completada';
GO
