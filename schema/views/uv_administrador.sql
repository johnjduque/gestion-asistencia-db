USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_administrador]
AS
SELECT		a.id,
			idUsuario = u.id,
			idTipoIdentificacionUsuario = u.idTipoIdentificacion,
			TipoIdentificacionUsuario = u.TipoIdentificacion,
			nombreTipoIdentificacionUsuario = u.nombreTipoIdentificacion,
			numeroIdentificacionUsuario = u.numeroIdentificacion,
			primerApellidoUsuario = u.primerApellido,
			segundoApellidoUsuario = u.segundoApellido,
			primerNombreUsuario = u.primerNombre,
			segundoNombreUsuario = u.segundoNombre,
			nombreCompletoUsuario = u.nombreCompleto,
			correoUsuario = u.correo,
			correoConfirmadoUsuario = u.correoConfirmado,
			correoConfirmadoTextoUsuario = u.correoConfirmadoTexto,
			estaActivoUsuario = u.estaActivoUsuario,
			estaActivoTextoUsuario = u.estaActivoTextoUsuario,
			passwordUsuario = u.password,

			idInstitucion = i.id,
			nombreInstitucion = i.nombre,
			estaActivaInstitucion = i.estaActivaInstitucion,
			estaActivoTextoInstitucion = i.estaActivaTextoInstitucion,

			idPerfil = u.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			nivelAccesoPerfil = p.nivel_acceso,
			estaActivoAdministrador = IIF(u.estaActivoUsuario = 0 OR i.estaActivaInstitucion = 0, 0, 1),
			estaActivoTextoAdministrador = IIF(u.estaActivoUsuario = 0 OR i.estaActivaInstitucion = 0, 'NO', 'SI'),
			justificacionEstado =	CASE
										WHEN u.estaActivoUsuario = 0 THEN CONCAT('Perfil ', p.nombre, ' inactivo porque usuario est? inactivo.')
										WHEN i.estaActivaInstitucion = 0 THEN CONCAT('Perfil ', p.nombre, ' inactivo porque instituci?n est? inactivd.')
										ELSE CONCAT('Perfil ', p.nombre, ' activo.')
									END
FROM		Administrador a
INNER JOIN	uv_usuario u
ON			a.usuario = u.id
INNER JOIN	uv_institucion i
ON			a.institucion = i.id,
			(SELECT TOP 1 id, codigo, nombre, nivel_acceso FROM uv_perfil WHERE codigo = 'AD') p
GO
