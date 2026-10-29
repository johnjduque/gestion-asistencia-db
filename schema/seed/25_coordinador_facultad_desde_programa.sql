USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121/HU122: relleno de Coordinador.facultad desde la facultad del programa que coordina.
-- schema/tables/Coordinador.sql hace el mismo relleno al crear la columna, pero en un despliegue limpio los
-- coordinadores (seed 12) y los programas (seed 13) se siembran DESPUES, y el coordinador sembrado quedaba con
-- facultad NULL (lo detecta T-DDL-02 en test_hu121_hu122_esquema_coordinador). Idempotente: solo toca NULL.
UPDATE c
SET    c.facultad = p.facultad
FROM   dbo.Coordinador c
INNER JOIN dbo.Programa p ON p.coordinador = c.id
WHERE  c.facultad IS NULL;
GO
