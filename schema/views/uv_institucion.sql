USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_institucion]
AS
SELECT	id,
		nombre,
		estaActivaInstitucion =  estado,
		estaActivaTextoInstitucion = IIF(estado = 1, 'SI', 'NO')
FROM	Institucion
GO
