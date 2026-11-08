-- CULM-001 D (CONTRACT §14.2): orden de rollback de los objetos compartidos entre subpaquetes de D. Cada subpaquete agrega aqui sus
-- casos D-RB-xx (D-RB-02 y D-RB-03 son de D.5 y D.9). Lo ejecuta test/test_culm001_d2.ps1 con sqlcmd -b y MIGDIR; la transaccion nunca
-- se confirma (la conexion termina en el error esperado).
--   D-RB-01  con la migracion 21 (D.2) aplicada, el down de la 20 (D.1) aborta con THROW 50020 SIN cambiar usp_radicar_solicitud_revision_asistencia_v2
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_up.sql
GO
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NULL
    THROW 57910, 'TEST FAILED: CULM001_D_RB_01 la migracion 21 no dejo v3 ni el interno.', 1;
PRINT 'RB01_UP21_OK';
GO
:r $(MIGDIR)/20_culm001_d1_plazo_justificacion_down.sql
GO
PRINT 'RB01_NOT_ENFORCED';
GO
ROLLBACK TRANSACTION;
GO
