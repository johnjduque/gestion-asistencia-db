-- ============================================================================
-- MIGRACION UP 70: correcciones de la auditoria de BD (2026-11-22), items M-11, M-1 y M-7.
--   M-11: ortografia (tildes) de 14 mensajes de usuario del catalogo (CatalogoMensajeUsuario; VAL_APP_068 tambien en CatalogoMensajeTecnico).
--   M-1:  indices de apoyo para las FK de ambito y filtro (IF NOT EXISTS; los mismos que declaran schema/tables/*.sql).
--   M-7:  retiro de tres objetos sin uso (ufn_obtener_estado_estudiante_grupo, usp_aplicar_festivos_grupo,
--         usp_consultar_oferta_creacion_grupo_docente).
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
PRINT 'MIGRACION 70 UP: completada';
GO
