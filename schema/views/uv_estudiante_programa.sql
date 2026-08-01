USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,
    
        idEstudiante = e.id,
        nombreEstudiante = e.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma

FROM		EstudiantePrograma ep
INNER JOIN	uv_estudiante e 
ON          ep.estudiante = e.id
INNER JOIN	uv_programa p   
ON          ep.programa = p.id
GO
