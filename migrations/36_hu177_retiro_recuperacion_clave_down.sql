-- ============================================================================
-- MIGRACION DOWN 36: sin efecto.
-- El up solo elimina los restos del flujo propio de recuperacion de contrasena (migracion 35, retirada del repositorio).
-- Ese flujo ya no existe aqui, asi que no hay nada que restaurar: la recuperacion la presta el servicio de seguridad de terceros.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 36 DOWN: sin efecto (el flujo retirado no se recrea)';
GO
