USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Vista: [dbo].[uv_area]
-- Descripción: Consulta canónica de áreas de conocimiento con total de asignaturas adscritas.
-- =============================================================================
CREATE OR ALTER VIEW [dbo].[uv_area]
AS
SELECT  
    a.id,
    a.codigo,
    a.nombre,
    totalAsignaturas = COUNT(asg.id)
FROM dbo.Area a
LEFT JOIN dbo.Asignatura asg ON asg.area = a.id
GROUP BY 
    a.id,
    a.codigo,
    a.nombre;
GO
