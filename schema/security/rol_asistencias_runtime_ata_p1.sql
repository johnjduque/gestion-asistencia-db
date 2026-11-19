USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): permisos del rol runtime para el aviso de falta por sesion. Aditivo e idempotente.
--   EXECUTE: usp_consultar_sesiones_pendientes_aviso_falta, usp_consultar_faltas_sesion_aviso y usp_registrar_aviso_falta_sesion
--   (comandos de sistema que invoca el job del backend). AvisoFaltaSesion no recibe permisos directos: se escribe solo por el SP.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_pendientes_aviso_falta] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_faltas_sesion_aviso] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_aviso_falta_sesion] TO [rol_asistencias_runtime];
GO
