-- ============================================================================
-- MIGRACION DOWN 62: restaura el texto anterior de MQR_008. Los cuerpos anteriores de los SP de la matricula por QR se restauran
-- desplegando el esquema de la version previa (deploy_schema.ps1), como en la 56 y la 61. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 62 DOWN: texto anterior de MQR_008';
GO
UPDATE dbo.CatalogoMensajeUsuario
SET contenido = N'No se pudo determinar tu programa en este grupo. Pide a tu docente que te matricule.', fechaModificacion = SYSUTCDATETIME()
WHERE codigo = 'MQR_008';
UPDATE dbo.CatalogoMensajeTecnico
SET contenido = N'Regla S3: el token no tiene programaPorDefecto y el grupo tiene varios programas.', fechaModificacion = SYSUTCDATETIME()
WHERE codigo = 'MQR_008';
GO
PRINT 'MIGRACION 62 DOWN OK';
GO
