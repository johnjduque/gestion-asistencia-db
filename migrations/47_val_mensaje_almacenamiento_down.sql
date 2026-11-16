-- ============================================================================
-- MIGRACION DOWN 47: retira ERR_ALMACENAMIENTO_NO_DISPONIBLE (REA-02, VAL-oleada9).
-- Sin la fila el backend responde con el texto de respaldo de su enum (el mismo significado). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 47 DOWN: retira ERR_ALMACENAMIENTO_NO_DISPONIBLE';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo = 'ERR_ALMACENAMIENTO_NO_DISPONIBLE';
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo = 'ERR_ALMACENAMIENTO_NO_DISPONIBLE';
GO
PRINT 'MIGRACION 47 DOWN: completada';
GO
