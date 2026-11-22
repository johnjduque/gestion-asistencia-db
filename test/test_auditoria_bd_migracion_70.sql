-- Auditoria de BD 2026-11-22: migracion 70 up -> down -> up.
-- Lo ejecuta test/test_auditoria_bd_migracion_70.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Parte de una BD ya desplegada
-- desde schema/ (con la 70). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   AUDBD_MIG70_UP1_OK      el up sobre una BD ya desplegada no cambia nada (idempotente)
--   AUDBD_MIG70_DOWN_OK     el down retira los 28 indices, restituye los textos anteriores de los 14 mensajes y recrea ufn_obtener_estado_estudiante_grupo
--   AUDBD_MIG70_UP2_OK      el up (dos veces) recrea los 28 indices, los textos con tilde y vuelve a retirar la funcion
--   AUDBD_MIG70_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF (SELECT COUNT(*) FROM sys.indexes WHERE name IN (N'IX_Grupo_docente', N'IX_Grupo_periodoAcademico', N'IX_Grupo_programaResponsable', N'IX_Horario_grupo', N'IX_Horario_dia', N'IX_DocentePrograma_programa', N'IX_EstudiantePrograma_programa', N'IX_Programa_facultad', N'IX_Programa_coordinador', N'IX_PlanEstudio_programa', N'IX_SemestrePlanEstudio_planEstudio', N'IX_Coordinador_facultad', N'IX_Coordinador_usuario', N'IX_Docente_usuario', N'IX_Estudiante_usuario', N'IX_Administrador_usuario', N'IX_Decano_usuario', N'IX_Facultad_decano', N'IX_EstudianteGrupo_estado', N'IX_DetalleAsistencia_razonCausa', N'IX_SolicitudRevisionAsistencia_estado', N'IX_SolicitudRevisionAsistencia_toma', N'IX_TomaAsistencia_estado', N'IX_TomaAsistencia_docenteApertura', N'IX_RevisionCancelacion_programaResolucion', N'IX_RevisionCancelacion_usuarioResolucion', N'IX_SesionSolicitud_usuarioSolicitante', N'IX_TokenMatriculaGrupo_docenteEmisor')) <> 28
   OR OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo') IS NOT NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido = N'El código de correlación es requerido.')
    THROW 59700, 'TEST FAILED: AUDBD_MIG70 la base inicial no tiene la 70 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/70_auditoria_bd_2026_11_22_up.sql
GO
PRINT 'AUDBD_MIG70_UP1_OK';
GO
:r $(MIGDIR)/70_auditoria_bd_2026_11_22_down.sql
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name IN (N'IX_Grupo_docente', N'IX_Grupo_periodoAcademico', N'IX_Grupo_programaResponsable', N'IX_Horario_grupo', N'IX_Horario_dia', N'IX_DocentePrograma_programa', N'IX_EstudiantePrograma_programa', N'IX_Programa_facultad', N'IX_Programa_coordinador', N'IX_PlanEstudio_programa', N'IX_SemestrePlanEstudio_planEstudio', N'IX_Coordinador_facultad', N'IX_Coordinador_usuario', N'IX_Docente_usuario', N'IX_Estudiante_usuario', N'IX_Administrador_usuario', N'IX_Decano_usuario', N'IX_Facultad_decano', N'IX_EstudianteGrupo_estado', N'IX_DetalleAsistencia_razonCausa', N'IX_SolicitudRevisionAsistencia_estado', N'IX_SolicitudRevisionAsistencia_toma', N'IX_TomaAsistencia_estado', N'IX_TomaAsistencia_docenteApertura', N'IX_RevisionCancelacion_programaResolucion', N'IX_RevisionCancelacion_usuarioResolucion', N'IX_SesionSolicitud_usuarioSolicitante', N'IX_TokenMatriculaGrupo_docenteEmisor'))
   OR OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo', N'FN') IS NULL
   OR dbo.ufn_obtener_estado_estudiante_grupo(NEWID(), NEWID()) <> N'NO INSCRITO'
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido = N'El codigo de correlacion es requerido.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ARC_003' AND contenido = N'Los datos del soporte no son validos.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'FES_007' AND contenido = N'El periodo académico no existe.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'VAL_APP_068' AND contenido = N'El campo dias es obligatorio cuando se envía el horario.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'VAL_APP_068' AND contenido LIKE N'%campo dias es obligatorio%envia el horario.')
    THROW 59701, 'TEST FAILED: AUDBD_MIG70 el down no retiro los indices, no restituyo los textos o no recreo la funcion.', 1;
PRINT 'AUDBD_MIG70_DOWN_OK';
GO
:r $(MIGDIR)/70_auditoria_bd_2026_11_22_up.sql
GO
:r $(MIGDIR)/70_auditoria_bd_2026_11_22_up.sql
GO
IF (SELECT COUNT(*) FROM sys.indexes WHERE name IN (N'IX_Grupo_docente', N'IX_Grupo_periodoAcademico', N'IX_Grupo_programaResponsable', N'IX_Horario_grupo', N'IX_Horario_dia', N'IX_DocentePrograma_programa', N'IX_EstudiantePrograma_programa', N'IX_Programa_facultad', N'IX_Programa_coordinador', N'IX_PlanEstudio_programa', N'IX_SemestrePlanEstudio_planEstudio', N'IX_Coordinador_facultad', N'IX_Coordinador_usuario', N'IX_Docente_usuario', N'IX_Estudiante_usuario', N'IX_Administrador_usuario', N'IX_Decano_usuario', N'IX_Facultad_decano', N'IX_EstudianteGrupo_estado', N'IX_DetalleAsistencia_razonCausa', N'IX_SolicitudRevisionAsistencia_estado', N'IX_SolicitudRevisionAsistencia_toma', N'IX_TomaAsistencia_estado', N'IX_TomaAsistencia_docenteApertura', N'IX_RevisionCancelacion_programaResolucion', N'IX_RevisionCancelacion_usuarioResolucion', N'IX_SesionSolicitud_usuarioSolicitante', N'IX_TokenMatriculaGrupo_docenteEmisor')) <> 28
   OR OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo') IS NOT NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido = N'El código de correlación es requerido.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ARC_003' AND contenido = N'Los datos del soporte no son válidos.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'FES_007' AND contenido = N'El período académico no existe.')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'VAL_APP_068' AND contenido LIKE N'%días%envía%')
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ERR_CORRELACION_REQUERIDA', 'ARC_003', 'FES_007', 'VAL_APP_068')) <> 4
    THROW 59702, 'TEST FAILED: AUDBD_MIG70 el up no recreo los indices, los textos con tilde o no retiro la funcion.', 1;
PRINT 'AUDBD_MIG70_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59703, 'TEST FAILED: AUDBD_MIG70 quedo una transaccion abierta.', 1;
PRINT 'AUDBD_MIG70_ROLLBACK_OK';
GO
