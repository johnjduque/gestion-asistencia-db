USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_id]    Script Date: 24/07/2026 8:59:10 p. m. ******/
DROP PROCEDURE [dbo].[usp_validar_id]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_id]    Script Date: 24/07/2026 8:59:10 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE	OR	ALTER	PROCEDURE [dbo].[usp_validar_id_interno]	(
									@id UNIQUEIDENTIFIER,
									@mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
									@mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
									@estadoResultado BIT OUTPUT
								)
AS
	DECLARE @idDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@id, '00000000-0000-0000-0000-000000000000'))));
BEGIN
	SELECT	@mensajeUsuarioResultado = 'No es posible llevar a cabo la operación solicitada, debido a que el identificado enviado, corresponde al valor por defecto o está vacío',
			@mensajeTecnicoResultado = 'No es posible llevar a cabo la operación solicitada, debido a que el identificado enviado, corresponde al valor por defecto o está vacío',
			@estadoResultado = 0
	WHERE	@idDefecto = '00000000-0000-0000-0000-000000000000'
END
GO


