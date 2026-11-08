USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM: catalogo de solo consulta del caracter de una asignatura en un plan.
CREATE OR ALTER VIEW [dbo].[uv_caracter_asignatura_plan]
AS
SELECT  id = c.id,
        codigo = c.codigo,
        nombre = c.nombre,
        orden = c.orden,
        estaActivo = c.estado
FROM    CaracterAsignaturaPlan c
GO
