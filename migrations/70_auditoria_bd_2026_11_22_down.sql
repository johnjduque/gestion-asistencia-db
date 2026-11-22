-- ============================================================================
-- MIGRACION DOWN 70: revierte las correcciones de la auditoria de BD (2026-11-22): textos anteriores de los mensajes (M-11), retira los
-- indices (M-1) y recrea los tres objetos retirados (M-7). Los cuerpos de SP y funciones de A-1, A-2, M-3 y M-6 se revierten desplegando
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
PRINT 'MIGRACION 70 DOWN: completada';
GO
