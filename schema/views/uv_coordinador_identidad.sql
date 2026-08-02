USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_coordinador_identidad]
AS
SELECT		c.id,
			idUsuario = u.id,
			u.numeroIdentificacion,
			u.nombreCompleto,
			u.estaActivoUsuario

FROM		Coordinador c
INNER JOIN	uv_usuario u 
ON			c.usuario = u.id
GO
