USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_programa]
AS
SELECT		pr.id,
			nombrePrograma = pr.nombre,
			pr.estado,
			
			idFacultad = f.id,
			nombreFacultad = f.nombreFacultad,
			idInstitucion = f.idInstitucion,
			nombreInstitucion = f.nombreInstitucion,
			
			idCoordinador = ci.id,
			nombreCoordinador = ci.nombreCompleto,
			
			estaActivoPrograma = pr.estado,
			estaActivoTextoPrograma = IIF(pr.estado = 1, 'SI', 'NO')

FROM		Programa pr
INNER JOIN	uv_facultad f 
ON			pr.facultad = f.id
LEFT JOIN	uv_coordinador_identidad ci 
ON			pr.coordinador = ci.id
GO
