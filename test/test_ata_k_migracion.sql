-- ATA D11 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS K.1): migracion 55 up -> down -> up.
-- Lo ejecuta test/test_ata_k_migracion.ps1 con sqlcmd y la variable MIGDIR (copia de migrations/). Parte de una BD ya desplegada
-- desde schema/ (sin el SP ni el parametro). Todo ocurre dentro de UNA transaccion que se revierte al final.
--   ATA_K_MIG_UP1_OK      el up sobre una BD limpia no cambia nada (idempotente)
--   ATA_K_MIG_DOWN_OK     el down recrea el SP, su EXECUTE para el rol runtime y el parametro en 1
--   ATA_K_MIG_UP2_OK      el up quita de nuevo el SP y el parametro (aunque tenga historial) y conserva la oferta del docente
--   ATA_K_MIG_ROLLBACK_OK la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES')
    THROW 59410, 'TEST FAILED: ATA_K_MIG la base inicial aun tiene la oferta del estudiante (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/55_ata_retiro_oferta_grupos_estudiante_up.sql
GO
PRINT 'ATA_K_MIG_UP1_OK';
GO
:r $(MIGDIR)/55_ata_retiro_oferta_grupos_estudiante_down.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES' AND valor = '1' AND valorDefecto = '1') <> 1
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                  WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante') AND dp.permission_name = N'EXECUTE'
                    AND dp.state_desc = N'GRANT' AND pr.name = N'rol_asistencias_runtime')
    THROW 59411, 'TEST FAILED: ATA_K_MIG el down no recreo el SP, su EXECUTE y el parametro.', 1;
PRINT 'ATA_K_MIG_DOWN_OK';
GO
-- Historial de cambios del parametro: el up debe poder borrarlo sin violar la FK.
INSERT INTO dbo.CambioParametro (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
SELECT NEWID(), p.id, N'1', N'0', N'prueba ATA D11', (SELECT TOP 1 id FROM dbo.Usuario ORDER BY id), NEWID(), SYSUTCDATETIME()
FROM dbo.CatalogoParametro p WHERE p.grupo = 'OFERTA' AND p.clave = 'INCLUIR_TRANSVERSALES';
GO
:r $(MIGDIR)/55_ata_retiro_oferta_grupos_estudiante_up.sql
GO
:r $(MIGDIR)/55_ata_retiro_oferta_grupos_estudiante_up.sql
GO
IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES')
   OR OBJECT_ID(N'dbo.usp_consultar_oferta_creacion_grupo_docente', N'P') IS NULL
    THROW 59412, 'TEST FAILED: ATA_K_MIG el up no retiro la oferta del estudiante o toco la del docente.', 1;
PRINT 'ATA_K_MIG_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59413, 'TEST FAILED: ATA_K_MIG quedo una transaccion abierta.', 1;
PRINT 'ATA_K_MIG_ROLLBACK_OK';
GO
