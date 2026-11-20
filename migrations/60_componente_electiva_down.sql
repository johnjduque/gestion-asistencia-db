-- ============================================================================
-- MIGRACION DOWN 60: retira COMP-ELE (componente electivas)
--   Elimina la fila ELE de dbo.Componente solo si ninguna asignatura la usa; si alguna la usa, se detiene sin cambios
--   (primero hay que reasignar esas asignaturas a otro componente). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 60 DOWN: retira COMP-ELE componente electivas';
GO
IF EXISTS (SELECT 1 FROM dbo.Asignatura WHERE componente = '9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E')
    THROW 59601, 'MIGRACION 60 DOWN: hay asignaturas con el componente ELE; reasignelas antes de retirarlo.', 1;
GO
DELETE FROM dbo.Componente WHERE id = '9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E';
GO
PRINT 'MIGRACION 60 DOWN: completada';
GO
