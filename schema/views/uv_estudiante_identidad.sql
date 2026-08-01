USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_estudiante_identidad]
AS
SELECT		e.id,
			idUsuario = u.id,
			u.numeroIdentificacion,
			u.nombreCompleto,
			u.estaActivoUsuario
FROM		Estudiante e
INNER JOIN	uv_usuario u 
ON			e.usuario = u.id
GO
