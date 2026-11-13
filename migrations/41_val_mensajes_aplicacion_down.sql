-- ============================================================================
-- MIGRACION DOWN 41: retira los mensajes VAL_APP_###, ACC_APP_###, NOF_APP_### y DIS_APP_### (VAL-oleada3 MSG-05).
-- Sin estas filas el backend responde con su texto de respaldo (el mismo significado). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 41 DOWN: retira los mensajes de usuario del backend';
GO
DELETE FROM dbo.CatalogoMensajeUsuario
WHERE codigo LIKE 'VAL[_]APP[_]___' OR codigo LIKE 'ACC[_]APP[_]___' OR codigo LIKE 'NOF[_]APP[_]___' OR codigo LIKE 'DIS[_]APP[_]___';
GO
DELETE FROM dbo.CatalogoMensajeTecnico
WHERE codigo LIKE 'VAL[_]APP[_]___' OR codigo LIKE 'ACC[_]APP[_]___' OR codigo LIKE 'NOF[_]APP[_]___' OR codigo LIKE 'DIS[_]APP[_]___';
GO
PRINT 'MIGRACION 41 DOWN OK';
GO
