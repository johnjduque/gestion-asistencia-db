-- ============================================================================
-- MIGRACION DOWN 40: retira AUDITORIA/RANGO_MAXIMO_DIAS (y su fila de edicion). NO revierte el ambito de las cuentas semilla de
-- ROL-12: dejarlas sin facultad ni programa reintroduciria el hallazgo H-03 y la asignacion es parte de la semilla.
-- Solo tiene sentido si el backend vuelve al valor fijo. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 40 DOWN: retira AUDITORIA/RANGO_MAXIMO_DIAS';
GO
DELETE e FROM dbo.CatalogoParametroEdicion e
INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
WHERE p.grupo = 'AUDITORIA' AND p.clave = 'RANGO_MAXIMO_DIAS';
GO
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'RANGO_MAXIMO_DIAS';
GO
PRINT 'MIGRACION 40 DOWN OK';
GO
