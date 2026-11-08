USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM: 1 fila por EstudiantePrograma, construida desde el vinculo y la identidad (ya no desde uv_estudiante).
CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,

        idEstudiante = e.id,
        nombreEstudiante = e.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma,
        estaActivoUsuario = e.estaActivoUsuario

FROM		EstudiantePrograma ep
INNER JOIN	uv_estudiante_identidad e
ON          ep.estudiante = e.id
INNER JOIN	uv_programa p
ON          ep.programa = p.id
GO
