-- ============================================================================
-- MIGRACION DOWN 67: retira ERR_BD_NO_DISPONIBLE.
-- Sin la fila el backend responde con el texto de respaldo de su enum (el mismo significado). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 67 DOWN: retira ERR_BD_NO_DISPONIBLE';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo = 'ERR_BD_NO_DISPONIBLE';
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo = 'ERR_BD_NO_DISPONIBLE';
GO
PRINT 'MIGRACION 67 DOWN: completada';
GO
