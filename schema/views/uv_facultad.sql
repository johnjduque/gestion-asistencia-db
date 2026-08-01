USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_facultad]
AS
SELECT		f.id,
			nombreFacultad = f.nombre,	
			idInstitucion = i.id,
			nombreInstitucion = i.nombre,
			idDecano = di.id,
			nombreCompletoDecano = di.nombreCompleto,
			estaActivaFacultad = f.estado,
			estaActivaTextoFacultad = IIF(f.estado = 1, 'SI', 'NO')

FROM		Facultad f
INNER JOIN	uv_institucion i 
ON			f.institucion = i.id
LEFT JOIN	uv_decano_identidad di 
ON			f.decano = di.id
GO
