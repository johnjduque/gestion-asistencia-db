USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_docente_identidad]
AS
SELECT		d.id,
			idUsuario = u.id,
			u.numeroIdentificacion,
			u.nombreCompleto,
			u.estaActivoUsuario
FROM		Docente d
INNER JOIN	uv_usuario u 
ON			d.usuario = u.id
GO
