-- ============================================================================
-- MIGRACION DOWN 72: retira el rotulo RPT_ASISTENCIA_ESTADO_CANCELADA. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA';
GO
PRINT 'MIGRACION 72 DOWN: completada';
GO
