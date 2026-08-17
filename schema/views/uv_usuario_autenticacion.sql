USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario_autenticacion]
AS
SELECT		idUsuario = u.id,
			correo = u.correo,
			password = u.password,
			correoConfirmado = u.correoConfirmado,
			estaActivoUsuario = u.estado

FROM		Usuario u
GO
