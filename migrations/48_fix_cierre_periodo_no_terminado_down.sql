-- ============================================================================
-- MIGRACION DOWN 48: retira PER_007 (FIX-CIERRE-002). Sin la fila, el cierre masivo de un periodo no terminado responde con el
-- texto generico del catalogo para un codigo ausente; el resto del catalogo no cambia. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 48 DOWN: retira PER_007';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo = 'PER_007';
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo = 'PER_007';
GO
PRINT 'MIGRACION 48 DOWN: completada';
GO
