-- CULM-001 D.2 (CONTRACT §3.2 D2-13): el down de la migracion 21 se niega a colapsar soportes sin confirmacion.
-- Con una solicitud que tiene DOS soportes ATTACHED (fixture) y SIN la variable CONFIRMAR_COLAPSO_SOPORTES = 1, el down debe
-- abortar con THROW 50021 y no cambiar nada. Lo ejecuta test/test_culm001_d2.ps1 con sqlcmd -b, MIGDIR y
-- CONFIRMAR_COLAPSO_SOPORTES=0; la transaccion nunca se confirma (la conexion termina en el error).
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_up.sql
GO
:r $(MIGDIR)/fixtures/culm001_d2_fixture.sql
GO
PRINT 'DOWN_SIN_CONFIRMACION_FIXTURE_OK';
GO
:r $(MIGDIR)/21_culm001_d2_soportes_categoria_down.sql
GO
PRINT 'DOWN_SIN_CONFIRMACION_NOT_ENFORCED';
GO
ROLLBACK TRANSACTION;
GO
