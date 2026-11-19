-- SES-GEN-01: migracion 59 up -> down -> up, dentro de una transaccion revertida.
--   SES_GEN_01_MIG_DOWN_OK       el down retira la columna, la vista/SP preview y los codigos nuevos, sin borrar ASI_009/ASI_010 de HU074
--   SES_GEN_01_MIG_UP1_OK        el up restaura columna, parametros y 13 mensajes SES-GEN-01
--   SES_GEN_01_MIG_UP2_OK        el up repetido conserva una sola copia de cada semilla
--   SES_GEN_01_MIG_ROLLBACK_OK   la base termina sin cambios
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario
       WHERE codigo IN ('HOR_006','HOR_007','HOR_008','HOR_009','HOR_010','HOR_011','HOR_012','HOR_013','HOR_014','ASI_013','ASI_014','PER_010','PER_011')) <> 13
    THROW 59970, 'TEST FAILED: SES_GEN_01_MIG falta el despliegue de SES-GEN-01 (schema/).', 1;
GO
:r $(MIGDIR)/59_ses_gen_01_calendario_semestre_down.sql
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_previsualizar_horario_grupo', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_periodo_academico_cierre', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_asignatura', N'V') IS NULL
   OR OBJECT_ID(N'dbo.uv_asignatura_plan_estudio', N'V') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('HOR_006','HOR_007','HOR_008','HOR_009','HOR_010','HOR_011','HOR_012','HOR_013','HOR_014','ASI_013','ASI_014','PER_010','PER_011'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('HOR_006','HOR_007','HOR_008','HOR_009','HOR_010','HOR_011','HOR_012','HOR_013','HOR_014','ASI_013','ASI_014','PER_010','PER_011'))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ASI_009','ASI_010')) <> 2
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'VAL_APP_076') <> 1
    THROW 59971, 'TEST FAILED: SES_GEN_01_MIG el down no retiro SES-GEN-01 o borro codigos de HU074.', 1;
SELECT TOP (0) * FROM dbo.uv_asignatura;
SELECT TOP (0) * FROM dbo.uv_asignatura_plan_estudio;
PRINT 'SES_GEN_01_MIG_DOWN_OK';
GO
:r $(MIGDIR)/59_ses_gen_01_calendario_semestre_up.sql
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Asignatura_horasSemanales' AND parent_object_id = OBJECT_ID(N'dbo.Asignatura'))
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario
       WHERE codigo IN ('HOR_006','HOR_007','HOR_008','HOR_009','HOR_010','HOR_011','HOR_012','HOR_013','HOR_014','ASI_013','ASI_014','PER_010','PER_011')) <> 13
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico
       WHERE codigo IN ('HOR_006','HOR_007','HOR_008','HOR_009','HOR_010','HOR_011','HOR_012','HOR_013','HOR_014','ASI_013','ASI_014','PER_010','PER_011')) <> 13
    THROW 59972, 'TEST FAILED: SES_GEN_01_MIG el up no restauro columna, restriccion y catalogos.', 1;
PRINT 'SES_GEN_01_MIG_UP1_OK';
GO
:r $(MIGDIR)/59_ses_gen_01_calendario_semestre_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_013') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ASI_014') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ASI_013') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'ASI_014') <> 1
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'PERIODO' AND clave = 'SEMANAS_DURACION') <> 1
    THROW 59973, 'TEST FAILED: SES_GEN_01_MIG el up repetido duplico mensajes o parametros.', 1;
PRINT 'SES_GEN_01_MIG_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0 THROW 59974, 'TEST FAILED: SES_GEN_01_MIG dejo una transaccion abierta.', 1;
PRINT 'SES_GEN_01_MIG_ROLLBACK_OK';
GO
