-- NOTOMA-001: migracion 57 up -> down -> up.
-- Lo ejecuta test/test_notoma_migraciones.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/).
-- Todo ocurre dentro de UNA transaccion que se revierte al final: la BD queda como estaba.
--   NOTOMA_MIG_DOWN_OK     el down quita los 3 SP, la tabla y los parametros, y conserva la plantilla y sus marcadores
--   NOTOMA_MIG_UP1_OK      el up recrea tabla (con FK), parametros, SP y permisos
--   NOTOMA_MIG_UP2_OK      el up repetido no cambia nada ni duplica semillas
--   NOTOMA_MIG_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.AvisoSesionSinToma', N'U') IS NULL OR OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NULL
    THROW 59600, 'TEST FAILED: NOTOMA_MIG la base inicial no tiene la migracion 57 (desplegar schema/ primero).', 1;
GO
:r $(MIGDIR)/57_notoma_aviso_sesion_sin_toma_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.AvisoSesionSinToma', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_SESION_SIN_TOMA')
    THROW 59601, 'TEST FAILED: NOTOMA_MIG el down de la 57 no quito el aviso de sesion sin toma.', 1;
IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR') <> 1
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR') <> 8
    THROW 59602, 'TEST FAILED: NOTOMA_MIG el down de la 57 debe conservar la plantilla y sus 8 marcadores.', 1;
PRINT 'NOTOMA_MIG_DOWN_OK';
GO
:r $(MIGDIR)/57_notoma_aviso_sesion_sin_toma_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NULL
   OR OBJECT_ID(N'dbo.AvisoSesionSinToma', N'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_AvisoSesionSinToma_Sesion')
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_SESION_SIN_TOMA') <> 3
   OR EXISTS (SELECT 1 FROM (VALUES (N'usp_consultar_sesiones_pendientes_aviso_sin_toma'), (N'usp_consultar_destinatarios_aviso_sin_toma'), (N'usp_registrar_aviso_sesion_sin_toma')) s(nombre)
              WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                                WHERE dp.major_id = OBJECT_ID(N'dbo.' + s.nombre, N'P') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
                                  AND pr.name = N'rol_asistencias_runtime'))
    THROW 59603, 'TEST FAILED: NOTOMA_MIG el up no dejo la tabla con su FK, los parametros, los SP y los permisos.', 1;
PRINT 'NOTOMA_MIG_UP1_OK';
GO
:r $(MIGDIR)/57_notoma_aviso_sesion_sin_toma_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_SESION_SIN_TOMA') <> 3
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR') <> 1
   OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_SIN_TOMA_COORDINADOR') <> 8
   OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE name = N'FK_AvisoSesionSinToma_Sesion') <> 1
    THROW 59604, 'TEST FAILED: NOTOMA_MIG el up repetido cambio objetos o duplico semillas.', 1;
PRINT 'NOTOMA_MIG_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
PRINT 'NOTOMA_MIG_ROLLBACK_OK';
GO
