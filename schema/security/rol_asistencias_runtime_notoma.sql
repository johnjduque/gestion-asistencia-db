USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTOMA-001: permisos del rol runtime para el aviso al coordinador de la sesion sin toma. Aditivo e idempotente.
--   EXECUTE: usp_consultar_sesiones_pendientes_aviso_sin_toma, usp_consultar_destinatarios_aviso_sin_toma y usp_registrar_aviso_sesion_sin_toma
--   (comandos de sistema que invoca el job del backend). AvisoSesionSinToma no recibe permisos directos: se escribe solo por el SP.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_aviso_sin_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_aviso_sesion_sin_toma] TO [rol_asistencias_runtime];
GO
