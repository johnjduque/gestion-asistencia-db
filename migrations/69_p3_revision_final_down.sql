-- ============================================================================
-- MIGRACION DOWN 69: retira los mensajes PER_012, EST_010 y EST_011 y restituye numeroSemana = numero en las sesiones manuales.
-- Los cuerpos de SP y vistas se revierten desplegando la version anterior del esquema (git). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 69 DOWN: retira mensajes y restituye numeroSemana = numero en sesiones manuales';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('PER_012', 'EST_010', 'EST_011');
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('PER_012', 'EST_010', 'EST_011');
GO
UPDATE s SET s.numeroSemana = s.numero
FROM dbo.Sesion s
WHERE s.numeroSemana <> s.numero AND EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss WHERE ss.sesion = s.id);
GO
PRINT 'MIGRACION 69 DOWN: completada';
GO
