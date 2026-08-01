USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario]
AS
SELECT		u.id,
			idTipoIdentificacion = ti.id,
			TipoIdentificacion = ti.tipoIdentificacion,
			nombreTipoIdentificacion = ti.nombre,
			numeroIdentificacion,
			primerApellido,
			segundoApellido,
			primerNombre,
			segundoNombre,
			nombreCompleto = CONCAT(LTRIM(RTRIM(CONCAT(primerNombre, ' ', segundoNombre))), ' ', LTRIM(RTRIM(CONCAT(primerApellido, ' ', segundoApellido)))),
			correo,
			correoConfirmado,
			correoConfirmadoTexto = IIF(correoConfirmado = 1, 'SI', 'NO'),
			estaActivoUsuario = estado,
			estaActivoTextoUsuario = IIF(estado = 1, 'SI', 'NO'),
			password = '*****'

FROM		Usuario u
INNER JOIN	uv_tipo_identificacion ti
ON			u.tipoIdIdentificacion = ti.id
GO
