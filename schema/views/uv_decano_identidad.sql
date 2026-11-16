USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_decano_identidad]
AS
SELECT		d.id,
			idUsuario = u.id,
			u.numeroIdentificacion,
			u.nombreCompleto,
			u.estaActivoUsuario,
			-- CIERRE-W1B (punto 4): nombres separados, al final para no mover las columnas previas
			u.primerNombre,
			u.segundoNombre,
			u.primerApellido,
			u.segundoApellido

FROM		Decano d
INNER JOIN	uv_usuario u 
ON			d.usuario = u.id
GO
